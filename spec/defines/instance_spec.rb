# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance', type: :define do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "with #{os}" do
        let(:facts) do
          os_facts
        end

        let(:title) do
          'test'
        end

        context 'when validating options' do
          context 'with an invalid title' do
            let(:title) do
              'bad name'
            end

            it { is_expected.to compile.and_raise_error(%r{must be a valid systemd service name}) }
          end

          context 'with default options' do
            it { is_expected.to compile.and_raise_error(%r{must specify a base_dn}) }
          end

          context 'with base_dn only specified' do
            let(:params) do
              {
                'base_dn' => 'ou=root,dn=my,dn=domain'
              }
            end

            it { is_expected.to compile.and_raise_error(%r{must specify a root_dn}) }
          end
        end

        context 'with valid options' do
          let(:params) do
            {
              'base_dn' => 'ou=root,dn=my,dn=domain',
              'root_dn' => 'cn=Directory Manager'
            }
          end

          it { is_expected.to compile.with_all_deps }

          it {
            expect(subject).to create_file("/usr/share/puppet_ds389_config/#{title}_ds_setup.inf")
              .with_owner('root')
              .with_group('root')
              .with_mode('0600')
              .with_selinux_ignore_defaults(true)
              .that_requires('Class[ds389::install]')
          }

          it {
            content = catalogue.resource("File[/usr/share/puppet_ds389_config/#{title}_ds_setup.inf]")[:content]

            require 'inifile'

            inifile = IniFile.new
            inifile = inifile.parse(content).to_h

            expect(inifile.keys.sort).to eq(['General', 'slapd', 'admin'].sort)
            expect(inifile['General'].keys.sort).to eq(
              [
                'SuiteSpotUserID',
                'SuiteSpotGroup',
                'AdminDomain',
                'FullMachineName',
                'ConfigDirectoryLdapURL',
                'ConfigDirectoryAdminID',
                'ConfigDirectoryAdminPwd',
              ].sort,
            )
            expect(inifile['General']['SuiteSpotUserID']).to eq('nobody')
            expect(inifile['General']['SuiteSpotGroup']).to eq('nobody')
            expect(inifile['General']['AdminDomain']).to eq(facts[:domain])
            expect(inifile['General']['FullMachineName']).to eq(facts[:fqdn])
            expect(inifile['General']['ConfigDirectoryLdapURL']).to eq("ldap://#{facts[:fqdn]}:389/o=NetscapeRoot")
            expect(inifile['General']['ConfigDirectoryAdminID']).to eq('admin')
            expect(inifile['General']['ConfigDirectoryAdminPwd']).to match(%r{^.+{8,}})

            expect(inifile['slapd'].keys.sort).to eq(
              [
                'ServerPort',
                'ServerIdentifier',
                'Suffix',
                'RootDN',
                'RootDNPwd',
                'SlapdConfigForMC',
                'AddOrgEntries',
                'AddSampleEntries',
              ].sort,
            )
            expect(inifile['slapd']['ServerPort']).to eq(389)
            expect(inifile['slapd']['ServerIdentifier']).to eq(title)
            expect(inifile['slapd']['Suffix']).to match(%r{^ou=root,(dn=.+,?){2}$})
            expect(inifile['slapd']['RootDN']).to eq('cn=Directory Manager')
            expect(inifile['slapd']['RootDNPwd']).to match(%r{^.+{8,}})
            expect(inifile['slapd']['SlapdConfigForMC']).to eq('yes')
            expect(inifile['slapd']['AddOrgEntries']).to eq('yes')
            expect(inifile['slapd']['AddSampleEntries']).to eq('no')

            expect(inifile['admin'].keys.sort).to eq(
              [
                'Port',
                'ServerAdminID',
                'ServerAdminPwd',
                'ServerIpAddress',
              ].sort,
            )

            expect(inifile['admin']['Port']).to eq(9830)
            expect(inifile['admin']['ServerAdminID']).to eq('admin')
            expect(inifile['admin']['ServerAdminPwd']).to match(%r{^.+{8,}})
            expect(inifile['admin']['ServerIpAddress']).to eq('127.0.0.1')
          }

          it {
            expect(subject).to create_exec("Setup #{title} DS")
              .with_command("/sbin/setup-ds.pl --silent -f /usr/share/puppet_ds389_config/#{title}_ds_setup.inf")
              .with_creates("/etc/dirsrv/slapd-#{title}/dse.ldif")
              .that_requires("File[/usr/share/puppet_ds389_config/#{title}_ds_setup.inf]")
              .that_notifies("Service[dirsrv@#{title}]")
          }

          it {
            expect(subject).to create_file('/usr/share/puppet_ds389_config')
              .with_ensure('directory')
              .with_owner('root')
              .with_group('nobody')
              .with_mode('u+rwx,g+x,o-rwx')
          }

          it {
            expect(subject).to create_file("/usr/share/puppet_ds389_config/#{title}_ds_pw.txt")
              .with_ensure('present')
              .with_owner('root')
              .with_group('root')
              .with_mode('0400')
              .that_requires("Exec[Setup #{title} DS]")
          }

          it {
            expect(subject).to create_file("/usr/share/puppet_ds389_config/#{title}_ds_pw.txt").with_content(%r{^(.+){8,}$})
          }

          it {
            expect(subject).to create_service("dirsrv@#{title}")
              .with_ensure('running')
              .with_enable(true)
              .with_hasrestart(true)
          }

          it {
            expect(subject).to create_ds389__config__item("Set nsslapd-listenhost on #{title}")
              .with_key('nsslapd-listenhost')
              .with_value('127.0.0.1')
              .with_admin_dn('cn=Directory Manager')
              .with_pw_file("/usr/share/puppet_ds389_config/#{title}_ds_pw.txt")
              .with_host('127.0.0.1')
              .with_port(389)
              .with_service_name(title)
          }

          it {
            expect(subject).to create_ds389__config__item("Set nsslapd-securelistenhost on #{title}")
              .with_key('nsslapd-securelistenhost')
              .with_value('127.0.0.1')
              .with_admin_dn('cn=Directory Manager')
              .with_pw_file("/usr/share/puppet_ds389_config/#{title}_ds_pw.txt")
              .with_host('127.0.0.1')
              .with_port(389)
              .with_service_name(title)
          }

          context 'when bootstrapping with an LDIF' do
            let(:params) do
              {
                base_dn: 'ou=root,dn=my,dn=domain',
                root_dn: 'cn=Directory Manager',
                bootstrap_ldif_content: 'some content'
              }
            end

            it { is_expected.to compile.with_all_deps }

            it {
              expect(subject).to create_file("/usr/share/puppet_ds389_config/#{title}_ds_bootstrap.ldif")
                .with_content(sensitive(params[:bootstrap_ldif_content]))
                .that_notifies("Exec[Setup #{title} DS]")
            }

            it do
              content = catalogue.resource("File[/usr/share/puppet_ds389_config/#{title}_ds_setup.inf]")[:content]

              require 'inifile'

              inifile = IniFile.new
              inifile = inifile.parse(content).to_h

              expect(inifile['slapd']['InstallLdifFile']).to eq("/usr/share/puppet_ds389_config/#{title}_ds_bootstrap.ldif")
            end
          end

          context 'when removing an instance' do
            let(:params) do
              {
                ensure: 'absent'
              }
            end

            it { is_expected.to compile.with_all_deps }

            it {
              expect(subject).to create_exec("Remove 389DS instance #{title}")
                .with_command("/sbin/remove-ds.pl -f -i slapd-#{title}")
                .with_onlyif("/bin/test -d /etc/dirsrv/slapd-#{title}")
            }
          end

          context 'with conflicting resource port' do
            let(:pre_condition) do
              <<~MANIFEST
              ds389::instance { 'pre_test':
                base_dn => 'ou=root,dn=my,dn=domain',
                root_dn => 'cn=Directory Manager'
              }
              MANIFEST
            end

            it {
              pending('https://github.com/puppetlabs/puppetlabs-stdlib/pull/1122')
              expect { expect(subject).to compile.with_all_deps }.to raise_error(%r{is already selected for use})
            }
          end

          context 'with ports in use on the host' do
            context 'when non-conflicting' do
              let(:facts) do
                os_facts.merge(
                  {
                    ds389__instances: {
                      'admin-srv' => {
                        'port' => 1234
                      },
                      "slapd-#{title}" => {
                        'port' => 389
                      },
                      'slapd-foo' => {
                        'port' => 333
                      }
                    }
                  },
                )
              end

              it { is_expected.to compile.with_all_deps }
            end

            context 'when conflicting' do
              let(:facts) do
                os_facts.merge(
                  {
                    ds389__instances: {
                      'admin-srv' => {
                        'port' => 1234
                      },
                      "slapd-#{title}" => {
                        'port' => 234
                      },
                      'slapd-foo' => {
                        'port' => 389
                      }
                    }
                  },
                )
              end

              it {
                expect { expect(subject).to compile.with_all_deps }.to raise_error(%r{is already in use})
              }
            end
          end
        end
      end
    end
  end
end

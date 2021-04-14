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
              'root_dn' => 'cn=Directory_Manager'
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

            expect(inifile.keys.sort).to eq(['General', 'slapd'].sort)
            expect(inifile['General'].keys.sort).to eq(
              [
                'SuiteSpotUserID',
                'SuiteSpotGroup',
                'FullMachineName',
                'ConfigDirectoryLdapURL',
              ].sort,
            )
            expect(inifile['General']['SuiteSpotUserID']).to eq('dirsrv')
            expect(inifile['General']['SuiteSpotGroup']).to eq('dirsrv')
            expect(inifile['General']['FullMachineName']).to eq(facts[:fqdn])
            expect(inifile['General']['ConfigDirectoryLdapURL']).to eq("ldap://#{facts[:fqdn]}:389/o=NetscapeRoot")

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
            expect(inifile['slapd']['RootDN']).to eq('cn=Directory_Manager')
            expect(inifile['slapd']['RootDNPwd']).to match(%r{^.+{8,}})
            expect(inifile['slapd']['SlapdConfigForMC']).to eq('yes')
            expect(inifile['slapd']['AddOrgEntries']).to eq('yes')
            expect(inifile['slapd']['AddSampleEntries']).to eq('no')
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
              .with_group('dirsrv')
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
            expect(subject).to create_ds389__instance__attr__set("Configure LDAPI for #{title}")
              .with_instance_name(title)
              .with_root_dn('cn=Directory_Manager')
              .with_host('127.0.0.1')
              .with_port(389)
              .with_restart_instance(true)
              .with_attrs(
                {
                  'cn=config' => {
                    'nsslapd-ldapilisten' => 'on',
                    'nsslapd-localssf' => 99_999
                  }
                },
              )
          }

          it {
            expect(subject).to create_ds389__instance__attr__set("Core configuration for #{title}")
              .with_instance_name(title)
              .with_root_dn('cn=Directory_Manager')
              .with_force_ldapi(true)
              .that_requires("Ds389::Instance::Attr::Set[Configure LDAPI for #{title}]")

            config_collection = catalogue.resource("Ds389::Instance::Attr::Set[Core configuration for #{title}]")[:attrs]
            expect(config_collection.keys).to eq(['cn=config'])

            attrs = config_collection['cn=config']
            expect(attrs['nsslapd-listenhost']).to eq('127.0.0.1')
            expect(attrs['nsslapd-securelistenhost']).to eq('127.0.0.1')
            expect(attrs['nsslapd-dynamic-plugins']).to eq('on')
            expect(attrs['nsslapd-allow-unauthenticated-binds']).to eq('off')
            expect(attrs['nsslapd-nagle']).to eq('off')
          }

          context 'with PKI' do
            let(:params) do
              {
                'base_dn' => 'ou=root,dn=my,dn=domain',
                'root_dn' => 'cn=Directory_Manager',
                'enable_tls' => true
              }
            end

            it { is_expected.to compile.with_all_deps }

            it {
              expect(subject).to create_ds389__instance__tls(title)
                .with_root_dn('cn=Directory_Manager')
                .with_root_pw_file('/usr/share/puppet_ds389_config/test_ds_pw.txt')
                .with_service_group('dirsrv')
                .with_ensure(params['enable_tls'])
                .with_source('/etc/pki/simp/ds389_test')
                .with_cert("/etc/pki/simp_apps/ds389_test/x509/public/#{facts[:fqdn]}.pub")
                .with_key("/etc/pki/simp_apps/ds389_test/x509/private/#{facts[:fqdn]}.pem")
                .with_cafile('/etc/pki/simp_apps/ds389_test/x509/cacerts/cacerts.pem')
                .with_dse_config({})
                .with_token(%r{^\S{32}$})
                .with_service_group('dirsrv')
            }
          end

          context 'when bootstrapping with an LDIF' do
            let(:params) do
              {
                base_dn: 'ou=root,dn=my,dn=domain',
                root_dn: 'cn=Directory_Manager',
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

          context 'with a conflicting resource port' do
            let(:pre_condition) do
              <<~MANIFEST
              ds389::instance { 'pre_test':
                base_dn => 'ou=root,dn=my,dn=domain',
                root_dn => 'cn=Directory_Manager'
              }
              MANIFEST
            end

            it {
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
                      title => {
                        'port' => 389
                      },
                      'foo' => {
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
                      title => {
                        'port' => 234
                      },
                      'foo' => {
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

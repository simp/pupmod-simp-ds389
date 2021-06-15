# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance::tls', type: :define do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "with #{os}" do
        let(:facts) do
          os_facts.merge({ :selinux_enforced => true })
        end

        let(:title) do
          'test'
        end

        let(:instance_base) do
            "/etc/dirsrv/slapd-#{title}"
        end

        let(:p12file) do
          "#{instance_base}/puppet_import.p12"
        end

        let(:pin_file) do
          "#{instance_base}/pin.txt"
        end

        let(:token_file) do
          "#{instance_base}/p12token.txt"
        end

        let(:pre_condition) do
          <<~PRECOND
          function assert_private(){}

          include ds389
          PRECOND
        end

        context 'with default parameters' do
          let(:params) do
            {
              root_dn: 'dn=thing',
              root_pw_file: '/some/seekrit/file.skrt',
              token: '12345678910111213' # For testing
            }
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to_not create_ds389__instance__selinux__port('636') }
          it { is_expected.to_not create_ds389__instance__attr__set("Do not require encryption for #{title}") }
          it { is_expected.to_not create_file(pin_file) }
          it { is_expected.to_not create_file(token_file) }
          it { is_expected.to_not create_pki__copy("ds389_#{title}") }
          it { is_expected.to_not create_exec("Validate #{title} p12") }
          it { is_expected.to_not create_exec("Build #{title} p12") }
          it { is_expected.to_not create_exec("Import #{title} p12") }
          it { is_expected.to_not create_exec("Import #{title} CA") }
          it { is_expected.to_not create_ds389__instance__dn__add("RSA DN for #{title}") }
          it { is_expected.to_not create_ds389__instance__attr__set("Configure PKI for #{title}") }
        end

        context 'with SIMP PKI' do
          let(:params) do
            {
              ensure: 'simp',
              root_dn: 'dn=thing',
              root_pw_file: '/some/seekrit/file.skrt',
              key: '/my/key',
              cert: '/my/cert',
              cafile: '/my/cafile',
              token: '12345678910111213' # For testing
            }
          end

          it { is_expected.to compile.with_all_deps }

          it do
            is_expected.to create_ds389__instance__selinux__port('636')
              .with_enable(true)
              .with_default(636)
          end

          it { is_expected.to_not create_ds389__instance__attr__set("Do not require encryption for #{title}") }

          it do
            is_expected.to create_file(pin_file)
            .with_group('dirsrv')
            .with_mode('0600')
            .with_content(sensitive("Internal (Software) Token:#{params[:token]}\n"))
          end

          it do
            is_expected.to create_file(token_file)
              .with_mode('0400')
              .with_content(sensitive(params[:token]))
          end

          it do
            expect(subject).to create_pki__copy("ds389_#{title}")
              .with_source(%r{/etc/pki})
              .with_pki(params[:ensure])
              .with_group('root')
              .that_notifies("Exec[Build #{title} p12]")
          end

          it do
            expect(subject).to create_exec("Validate #{title} p12")
              .with_command("rm -f #{p12file}")
              .with_unless("openssl pkcs12 -nokeys -in #{p12file} -passin file:#{token_file}")
              .with_path(['/bin', '/usr/bin'])
              .that_notifies("Exec[Build #{title} p12]")
          end

          it do
            expect(subject).to create_exec("Build #{title} p12")
              .with_command("openssl pkcs12 -export -name 'Server-Cert' -out #{p12file} -in #{params[:key]} -certfile #{params[:cert]} -passout file:#{token_file}")
              .with_refreshonly(true)
              .with_path(['/bin', '/usr/bin'])
              .that_subscribes_to("File[#{token_file}]")
          end

          it do
            expect(subject).to create_exec("Import #{title} p12")
              .with_command("certutil -D -d #{instance_base} -n 'Server-Cert' ||:; pk12util -i #{p12file} -d #{instance_base} -w #{token_file} -k #{token_file} -n 'Server-Cert'")
              .with_path(['/bin', '/usr/bin'])
              .that_subscribes_to("File[#{token_file}]")
          end

          it do
            expect(subject).to create_exec("Import #{title} CA")
              .with_command("certutil -D -d #{instance_base} -n 'CA Certificate' ||:; certutil -A -i #{params[:cafile]} -d #{instance_base} -n 'CA Certificate' -t 'CT,,' -a -f #{token_file}")
              .with_path(['/bin', '/usr/bin'])
              .that_subscribes_to("Exec[Build #{title} p12]")
          end

          it { is_expected.to create_ds389__instance__dn__add("RSA DN for #{title}").with_force_ldapi(true) }

          it do
            expect(subject).to create_ds389__instance__attr__set("Configure PKI for #{title}")
              .with_force_ldapi(true)
              .with_restart_instance(true)
              .that_requires("Ds389::Instance::Dn::Add[RSA DN for #{title}]")
          end

          it do
            expect(
              catalogue.resource("Ds389::Instance::Attr::Set[Configure PKI for #{title}]")[:attrs],
            ).to match(
              {
                'cn=encryption,cn=config' => {
                  'allowWeakCipher' => 'off',
                  'allowWeakDHParam' => 'off',
                  'nsSSL2' => 'off',
                  'nsSSL3' => 'off',
                  'nsSSLClientAuth' => 'required',
                  'nsTLS1' => 'on',
                  'nsTLSAllowClientRenegotiation' => 'on',
                  'sslVersionMax' => 'TLS1.2',
                  'sslVersionMin' => 'TLS1.2',
                  'nsSSL3Ciphers' => %r{AES_256}
                },
                'cn=config' => {
                  'nsslapd-ssl-check-hostname' => 'on',
                  'nsslapd-validate-cert' => 'on',
                  'nsslapd-minssf' => 256,
                  'nsslapd-require-secure-binds' => 'on',
                  'nsslapd-security' => 'on',
                  'nsslapd-securePort' => 636
                }
              },
            )
          end
        end

        context 'with non-SIMP PKI' do
          let(:params) do
            {
              ensure: true,
              root_dn: 'dn=thing',
              root_pw_file: '/some/seekrit/file.skrt',
              key: '/my/key',
              cert: '/my/cert',
              cafile: '/my/cafile',
              token: '12345678910111213' # For testing
            }
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to create_ds389__instance__selinux__port('636').with_enable(true) }
          it { is_expected.to create_file(pin_file) }
          it { is_expected.to create_file(token_file) }

          it do
            expect(subject).to create_pki__copy("ds389_#{title}")
              .with_source(%r{/etc/pki})
              .with_pki(params[:ensure])
              .with_group('root')
              .that_notifies("Exec[Build #{title} p12]")
          end

          it { is_expected.to create_exec("Validate #{title} p12") }
          it { is_expected.to create_exec("Build #{title} p12") }
          it { is_expected.to create_exec("Import #{title} p12") }
          it { is_expected.to create_exec("Import #{title} CA") }
          it { is_expected.to create_ds389__instance__dn__add("RSA DN for #{title}") }
          it { is_expected.to create_ds389__instance__attr__set("Configure PKI for #{title}") }
        end

        context 'with PKI disabled' do
          let(:params) do
            {
              root_dn: 'dn=thing',
              root_pw_file: '/some/seekrit/file.skrt',
              :ensure => 'disabled'
            }
          end

          context 'when 389ds instance available in facts' do

              let(:facts) do
                os_facts.merge(
                  {
                    selinux_enforced: true,
                    ds389__instances: {
                      title => {
                        'port'       => 389,
                        'securePort' => 636
                      }
                    }
                  }
                )
              end

            it { is_expected.to compile.with_all_deps }
            it do
              is_expected.to create_ds389__instance__selinux__port('636')
                .with_enable(false)
                .with_default(636)
            end

            it do
              expect(subject).to create_ds389__instance__attr__set("Do not require encryption for #{title}")
                .with_instance_name(title)
                .with_root_dn(params[:root_dn])
                .with_root_pw_file(params[:root_pw_file])
                .with_force_ldapi(true)
                .with_key('nsslapd-minssf')
                .with_value('0')
            end

            it { is_expected.to_not create_file(pin_file) }
            it { is_expected.to_not create_file(token_file) }
            it { is_expected.to_not create_pki__copy("ds389_#{title}") }
            it { is_expected.to_not create_exec("Validate #{title} p12") }
            it { is_expected.to_not create_exec("Build #{title} p12") }
            it { is_expected.to_not create_exec("Import #{title} p12") }
            it { is_expected.to_not create_exec("Import #{title} CA") }
            it { is_expected.to_not create_ds389__instance__dn__add("RSA DN for #{title}") }
            it { is_expected.to_not create_ds389__instance__attr__set("Configure PKI for #{title}") }
          end

          context 'when 389ds instance not available in facts' do
            it { is_expected.to compile.with_all_deps }
            it { is_expected.to_not create_ds389__instance__selinux__port('636') }
            it { is_expected.to create_ds389__instance__attr__set("Do not require encryption for #{title}") }
          end
        end
      end
    end
  end
end

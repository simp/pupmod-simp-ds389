# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name '389DS with PKI'

describe '389DS with PKI' do
  let(:manifest) do
    'include ds389'
  end

  hosts_with_role(hosts, 'directory_server').each do |host|
    context "ds389 class on #{host} " do
      let(:base_dn) { 'dc=tls,dc=com' }
      let(:rootpasswd) { 'password' }
      let(:root_dn) { 'cn=Directory_Manager' }
      let(:bootstrapldif) { ERB.new(File.read(File.expand_path('files/bootstrap.ldif.erb', File.dirname(__FILE__)))).result(binding) }
      let(:fqdn) {  fact_on(host, 'fqdn').strip }
      let(:certdir) { '/etc/pki/simp-testing/pki' }

      # assumes hieradata, port_starttls, port_tls, and ds_root_name are available
      # in the context
      shared_examples_for 'a TLS-enabled 389ds instance' do |shared_host|
        it 'works with no errors' do
          set_hieradata_on(shared_host, hieradata)
          apply_manifest_on(shared_host, manifest, catch_failures: true)
        end

        it 'is idempotent' do
          apply_manifest_on(shared_host, manifest, catch_changes: true)
        end

        it 'can not login to 389DS unencrypted' do
          expect { on(shared_host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -h #{fqdn} -b "cn=tasks,cn=config")) }.to raise_error(%r{.+})
        end

        it 'sets the environment variables for ldapsearch' do
          shared_host.add_env_var('LDAPTLS_CACERT', "#{certdir}/cacerts/cacerts.pem")
          shared_host.add_env_var('LDAPTLS_KEY', "#{certdir}/private/#{fqdn}.pem")
          shared_host.add_env_var('LDAPTLS_CERT', "#{certdir}/public/#{fqdn}.pub")
        end

        it 'can login to 389DS using STARTTLS' do
          on(shared_host, %(ldapsearch -ZZ -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldap://#{fqdn}:#{port_starttls} -b "cn=tasks,cn=config"))
        end

        it 'can login to 389DS using LDAPS' do
          on(shared_host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldaps://#{fqdn}:#{port_tls} -b "cn=tasks,cn=config"))
        end

        it 'can login to 389DS via LDAPI' do
          on(shared_host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
        end

        it 'reports 389ds instance facts' do
          results = pfact_on(shared_host, 'ds389__instances')
          puts "Fact ds389__instances = #{results}"
          expect(results.to_s).not_to be_empty
          instance_name = hieradata['ds389::instances'].keys.first
          instance_config = hieradata['ds389::instances'][instance_name]
          expect(results.key?(instance_name)).to be true

          # spot check a few key details in the facts
          expect(results[instance_name]['rootdn']).to eq(instance_config['root_dn'])
          expect(results[instance_name]['require-secure-binds']).to be true

          port = instance_config.key?('port') ? instance_config['port'] : 389
          expect(results[instance_name]['port']).to eq(port)

          secure_port = instance_config.key?('secure_port') ? instance_config['secure_port'] : 636
          expect(results[instance_name]['securePort']).to eq(secure_port)
        end

        it 'unsets the environment variables for ldapsearch' do
          shared_host.clear_env_var('LDAPTLS_CERT')
          shared_host.clear_env_var('LDAPTLS_KEY')
          shared_host.clear_env_var('LDAPTLS_CACERT')
        end
      end

      context 'with default ports' do
        let(:ds_root_name) { 'test_tls' }
        let(:port_starttls) { 389 }
        let(:port_tls) { 636 }
        let(:hieradata) do
          {
            'ds389::instances' => {
              ds_root_name => {
                'base_dn'          => base_dn,
                'root_dn'          => root_dn,
                'root_dn_password' => rootpasswd,
                'listen_address'   => '0.0.0.0',
                'enable_tls'       => true,
                'tls_params'       => {
                  'source' => certdir
                }
              }
            }
          }
        end

        it_behaves_like 'a TLS-enabled 389ds instance', host
      end

      context 'with custom ports' do
        let(:ds_root_name) { 'test_tls_custom_ports' }
        let(:port_starttls) { 388 }
        let(:port_tls) { 635 }
        let(:hieradata) do
          {
            'ds389::instances' => {
              ds_root_name => {
                'base_dn'          => base_dn,
                'root_dn'          => root_dn,
                'root_dn_password' => rootpasswd,
                'listen_address'   => '0.0.0.0',
                'port'             => port_starttls,
                'secure_port'      => port_tls,
                'enable_tls'       => true,
                'tls_params' => {
                  'source' => certdir
                }
              }
            }
          }
        end

        it_behaves_like 'a TLS-enabled 389ds instance', host

        context 'when removing a server instance with custom ports' do
          let(:manifest) { %(ds389::instance { #{ds_root_name}: ensure => "absent" }) }
          let(:hieradata) { { 'unused::tag' => true } }

          it 'clears the hieradata' do
            set_hieradata_on(host, hieradata)
          end

          it 'removes the server instance' do
            expect(directory_exists_on(host, "/etc/dirsrv/slapd-#{ds_root_name}")).to be true
            apply_manifest_on(host, manifest, catch_failures: true)

            expect(directory_exists_on(host, "/etc/dirsrv/slapd-#{ds_root_name}")).to be false
          end

          it 'is idempotent' do
            apply_manifest_on(host, manifest, catch_changes: true)
          end
        end
      end
    end
  end
end

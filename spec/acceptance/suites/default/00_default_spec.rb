# frozen_string_literal: true

require 'spec_helper_acceptance'

test_name 'Set up 389DS'

describe 'Set up 389DS' do
  let(:manifest) do
    'include ds389'
  end

  unless hosts.find { |h| h[:hypervisor] == 'docker' }
    hosts.each do |host|
      context "on #{host}" do
        it 'has a proper FQDN' do
          on(host, "hostname #{fact_on(host, 'fqdn')}")
          on(host, 'hostname -f > /etc/hostname')
        end
      end
    end
  end

  hosts_with_role(hosts, 'directory_server').each do |host|

    context 'with default setup' do
      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'is not running any slapd instances' do
        expect(on(host, 'ls /etc/dirsrv/slapd-*', accept_all_exit_codes: true).stdout.strip).to be_empty
      end
    end


    context 'create an instance' do
      let(:base_dn) { 'dc=test,dc=com' }
      let(:rootpasswd) { 'password'}
      let(:root_dn) { 'cn=Directory_Manager' }
      let(:root_dn_pwd) { on(host, "/usr/bin/pwdhash -s SHA256 #{rootpasswd}").output.strip }
      let(:bootstrapldif) { ERB.new(File.read(File.expand_path('files/bootstrap.ldif.erb',File.dirname(__FILE__)))).result(binding) }
      let(:ds_root_name) { 'test_in'}

      let(:manifest) { <<-EOM
          ds389::instance { "#{ds_root_name}":
            base_dn                => '#{base_dn}',
            root_dn                => '#{root_dn}',
            root_dn_password       => '#{rootpasswd}',
            bootstrap_ldif_content => '#{bootstrapldif}',
            enable_tls             => false
            }
      EOM
      }


      it 'works with no errors' do
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'is running ns-slapd' do
        apply_manifest_on(host, 'package { "iproute": ensure => installed }')
        on(host, 'ps -u dirsrv')
        on(host, 'ss -tlpn | grep :389')
      end

      it 'can login to 389DS' do
        on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -h localhost -b "cn=tasks,cn=config"))
      end

      it 'can login to 389DS via LDAPI' do
        on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
      end

      it 'contains the entries from the ldif' do

        result = on(host, %(ldapsearch -x -w "#{rootpasswd}" -D "#{root_dn}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "#{base_dn}")).output

        expect(result.lines.grep(%r{cn=administrators,ou=Group,#{base_dn}})).not_to be_empty
      end

      it 'fails when logging in with forced encryption' do
        expect { on(host, %(ldapsearch -ZZ -x -w "#{rootpasswd}" -D "#{root_dn}" -h `hostname -f` -b "cn=tasks,cn=config")) }.to raise_error(Beaker::Host::CommandFailure)
      end

      it 'reports 389ds instance facts for single instance' do
        results = pfact_on(host, 'ds389__instances')
        puts "Fact ds389__instances = #{results}"
        expect( results.to_s ).to_not be_empty
        expect( results.keys).to eq ['test_in']

        # check the details in the facts
        details = results['test_in']
        expect( details['ldapifilepath'] ).to eq('/var/run/slapd-test_in.socket')
        expect( details['ldapilisten'] ).to be true
        expect( details['listenhost'] ).to eq('127.0.0.1')
        expect( details['port'] ).to eq(389)
        expect( details.key?('require-secure-binds') ).to be false
        expect( details['rootdn'] ).to eq('cn=Directory_Manager')
        expect( details.key?('securePort') ).to be false
      end
    end

    context 'create an instance on a custom port' do
      # Let passgen auto generate the password and get the password from the file.
      let(:root_dn_password_file) do
        "/usr/share/puppet_ds389_config/#{ds_root_name}_ds_pw.txt"
      end

      let(:ds_root_name) { 'scrap' }
      let(:hieradata) do
        {
          'ds389::instances'                     => {
            ds_root_name => {
              'base_dn' => 'dc=scrap test,dc=space',
              'root_dn' => 'cn=Scrap_Admin',
              'listen_address' => '0.0.0.0',
              'port' => 388
            }
          }
        }
      end

      it 'enables the instance' do
        set_hieradata_on(host, hieradata)
        apply_manifest_on(host, manifest, catch_failures: true)
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'is running the dirsrv@test_in service' do
        status = YAML.safe_load(
          on(host, 'puppet resource --to_yaml service dirsrv@test_in')
          .stdout
        )

        expect(status['service']['dirsrv@test_in']['ensure']).to eq('running')
      end

      it 'can login to 389DS' do
        # rubocop:disable Layout/LineLength
        on(host, %(ldapsearch -x -y "#{root_dn_password_file}" -D "#{hieradata['ds389::instances'][ds_root_name]['root_dn']}" -H ldapi://%2fvar%2frun%2fslapd-#{ds_root_name}.socket -b "cn=tasks,cn=config"))
        # rubocop:enable Layout/LineLength
      end

      it 'reports 389ds instance facts for both instances' do
        results = pfact_on(host, 'ds389__instances')
        puts "Fact ds389__instances = #{results}"
        expect( results.to_s ).to_not be_empty
        expect( results.keys.sort ).to eq ['scrap', 'test_in']

        # check the details in the facts
        test_in_details = results['test_in']
        expect( test_in_details['ldapifilepath'] ).to eq('/var/run/slapd-test_in.socket')
        expect( test_in_details['ldapilisten'] ).to be true
        expect( test_in_details['listenhost'] ).to eq('127.0.0.1')
        expect( test_in_details['port'] ).to eq(389)
        expect( test_in_details.key?('require-secure-binds') ).to be false
        expect( test_in_details['rootdn'] ).to eq('cn=Directory_Manager')
        expect( test_in_details.key?('securePort') ).to be false

        scrap_details = results['scrap']
        expect( scrap_details['ldapifilepath'] ).to eq('/var/run/slapd-scrap.socket')
        expect( scrap_details['ldapilisten'] ).to be true
        expect( scrap_details['listenhost'] ).to eq('0.0.0.0')
        expect( scrap_details['port'] ).to eq(388)
        expect( scrap_details.key?('require-secure-binds') ).to be false
        expect( scrap_details['rootdn'] ).to eq('cn=Scrap_Admin')
        expect( scrap_details.key?('securePort') ).to be false
      end

      it 'starts after reboot' do
        host.reboot
        status = YAML.safe_load(
          on(host, 'puppet resource --to_yaml service dirsrv@test_in')
          .stdout
        )

        expect(status['service']['dirsrv@test_in']['ensure']).to eq('running')
      end
    end

    context 'when removing server instances' do
      let(:manifest) do
        <<~MANIFEST
          ds389::instance { "scrap": ensure => "absent" }
          ds389::instance { "test_in": ensure => "absent" }
          MANIFEST
      end
      let(:hieradata) do
        { 'ds389::initialize_ds_root' => true }
      end

      it 'clears the hieradata' do
        set_hieradata_on(host, hieradata)
      end

      it 'removes the server instances' do
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-scrap')).to be true
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-test_in')).to be true

        apply_manifest_on(host, manifest, catch_failures: true)

        expect(directory_exists_on(host, '/etc/dirsrv/slapd-scrap')).to be false
        expect(directory_exists_on(host, '/etc/dirsrv/slapd-test_in')).to be false
      end

      it 'is idempotent' do
        apply_manifest_on(host, manifest, catch_changes: true)
      end

      it 'reports no 389ds instance facts' do
        results = pfact_on(host, 'ds389__instances')
        puts "Fact ds389__instances = #{results}"
        expect( results ).to be_empty
      end
    end
  end
end

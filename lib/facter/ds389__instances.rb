# frozen_string_literal: true

# Return a Hash of the various DS389 instances on the system
#
# @example Instances
#   {
#     # Present if the admin server is running
#     'admin-srv' => {
#       'port' => 9830
#     },
#     'slapd-puppet_default_root' => {
#       'port' => 389
#     },
#     'slapd-test_instance' => {
#       'port' => 390
#     }
#   }
#
Facter.add('ds389__instances') do
  confdir = '/etc/dirsrv'

  confine { File.directory?(confdir) }

  setcode do
    instances = {}

    admin_srv_dir = File.join(confdir, 'admin-srv')
    if File.directory?(admin_srv_dir)
      admin_srv_local_conf = File.join(admin_srv_dir, 'local.conf')

      if File.exist?(admin_srv_local_conf)
        admin_srv_port = File.read(admin_srv_local_conf).lines.grep(
          %r{configuration.nsserverport:\s+(\d+)},
        ) { Regexp.last_match(1).to_i }.first

        instances['admin-srv'] = { 'port' => admin_srv_port } if admin_srv_port
      end
    end

    Dir.glob(File.join(confdir, 'slapd-*')) do |slapd_svr|
      next if slapd_svr =~ %r{\.removed$}

      slapd_svr_conf = File.join(slapd_svr, 'dse.ldif')

      if File.exist?(slapd_svr_conf)
        instance_name = File.basename(slapd_svr)
        slapd_svr_conf_content = File.read(slapd_svr_conf).lines

        slapd_svr_conf_content.grep(%r{nsslapd-(port|listenhost):\s}).each do |config_item|
          key, value = config_item.split(': ')

          if key.include?('-listenhost')
            instances[instance_name] ||= {}
            instances[instance_name]['address'] = value.to_i
          elsif key.include?('-port')
            instances[instance_name] ||= {}
            instances[instance_name]['port'] = value.to_i
          end
        end
      end
    end

    instances
  end
end

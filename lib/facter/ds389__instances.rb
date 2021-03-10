# frozen_string_literal: true

#
# Return a Hash of the various DS389 instances on the system with limited
# configuration details
#
# @example Instances
#   {
#     # Present if the admin server is running
#     'admin-serv' => {
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
    # Add things that we want to collect to this list
    settings_of_interest = [
      'nsslapd-ldapifilepath',
      'nsslapd-ldapilisten',
      'nsslapd-listenhost',
      'nsslapd-port',
      'nsslapd-require-secure-binds',
      'nsslapd-rootdn',
    ]

    instances = {}

    admin_srv_dir = File.join(confdir, 'admin-serv')
    if File.directory?(admin_srv_dir)
      admin_srv_local_conf = File.join(admin_srv_dir, 'local.conf')

      if File.exist?(admin_srv_local_conf)
        admin_srv_port = File.read(admin_srv_local_conf).lines.grep(
          %r{configuration.nsserverport:\s+(\d+)},
        ) { Regexp.last_match(1).to_i }.first

        instances['admin-serv'] = { 'port' => admin_srv_port } if admin_srv_port
      end
    end

    Dir.glob(File.join(confdir, 'slapd-*')) do |slapd_svr|
      next if slapd_svr =~ %r{\.removed$}

      slapd_svr_conf = File.join(slapd_svr, 'dse.ldif')

      if File.exist?(slapd_svr_conf)
        instance_name = File.basename(slapd_svr).split('slapd-').last

        conf_section = ''

        # Extract the configuration section
        in_config = false
        File.read(slapd_svr_conf).lines.each do |confline|
          break if in_config && confline.strip.empty?

          if confline.strip == 'dn: cn=config'
            in_config = true
            next
          end

          conf_section = "#{conf_section}#{confline}" if in_config
        end

        # Combine multi-part lines
        conf_hash = {}
        conf_section.gsub(%r{\n\s+}, '').lines.each do |confline|
          key, value = confline.split(': ')
          next unless value

          key.strip!
          value.strip!

          if conf_hash[key]
            conf_hash[key] ||= []
            conf_hash[key] << value
          else
            conf_hash[key] = value
          end
        end

        # Manipulate the settings
        settings_of_interest.each do |setting|
          entry = conf_hash[setting]
          next unless entry

          key = setting.split('nsslapd-').last
          value = entry
          if ['on', 'true'].include?(value)
            value = true
          elsif ['off', 'false'].include?(value)
            value = false
          elsif value =~ %r{^\d+$}
            value = value.to_i
          end

          instances[instance_name] ||= {}
          instances[instance_name][key] = value
        end

        # Fixup troublesome items
        if instances[instance_name]['ldapilisten']
          instances[instance_name]['ldapilisten'] = File.exist?((instances[instance_name]['ldapifilepath']).to_s)
        end
      end
    end

    instances
  end
end

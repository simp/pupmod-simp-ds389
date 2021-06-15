# Modifies the running directory server configuration and restarts the service
# when necessary.
#
# NOTE: When calling this defined type as you first set up an instance, you
# will need to pass in all parameters since the fact will not yet be fully
# populated.
#
# @option name [String]
#   A globally unique description of the desired configuration setting
#
# @param key
#   The configuration key to be set
#
#     * You can get a list of all configuration keys by running:
#       ``ldapsearch -H ldap://localhost:389 \
#       -y /usr/share/puppet_ds389_config/<instance_name>_ds_pw.txt \
#       -D "cn=Directory_Manager" -s base -b "cn=config"``
#     * Mutually exclusive with `$attrs`
#     * `$value` must be set when using this parameter.
#
# @param value
#   The value that should be set for `$key`
#
# @param attrs
#   Hash of attributes to be set.
#
#     * You can get a list of all configuration keys by running:
#       ``ldapsearch -H ldap://localhost:389 \
#       -y /usr/share/puppet_ds389_config/<instance_name>_ds_pw.txt \
#       -D "cn=Directory_Manager" -s base -b "cn=config"``
#     * Mutually exclusive with `$key`
#
# @param base_dn
#   The base DN under which to search
#
# @param instance_name
#   The Puppet resource name for the directory ``Service`` resource
#
# @param root_dn
#   A DN with administrative rights to the directory
#
#   * Will be determined automatically if not set
#
# @param root_pw_file
#   A file containing the password for use with ``$root_dn``
#
#   * Defaults to `$ds389::config_dir/<usual pw file>`
#
# @param host
#   The host to which to connect
#
#   * Has no effect if LDAPI is enabled on the instance
#   * Will use 127.0.01 if not set
#
# @param port
#   The port to which to connect
#
#   * Has no effect if LDAPI is enabled on the instance
#   * Will be determined automatically if not set
#
# @param force_ldapi
#   Force the system to use the LDAPI interface
#
#   * Generally only useful during bootstrapping
#
# @param restart_instance
#   Whether or not to restart the directory server after applying this item
#
#   * This may be enabled automatically by `$attrs`
#
define ds389::instance::attr::set (
  Simplib::Systemd::ServiceName  $instance_name,
  Optional[String[1]]            $key              = undef,
  Optional[String[1]]            $value            = undef,
  Ds389::ConfigItems             $attrs            = {},
  String[2]                      $base_dn          = 'cn=config',
  Optional[String[2]]            $root_dn          = undef,
  Optional[Stdlib::Absolutepath] $root_pw_file     = undef,
  Optional[Simplib::Host]        $host             = undef,
  Optional[Simplib::Port]        $port             = undef,
  Boolean                        $force_ldapi      = false,
  Boolean                        $restart_instance = false
) {
  $_instance_name = split($instance_name, /^(dirsrv@)?slapd-/)[-1]

  if !$key and !$value and empty($attrs) {
    fail('You must specify either $key and $value or $attrs')
  }
  if ($key and !$value) or ($value and !$key) {
    fail('You must specify both $key and $value if one is specified')
  }
  if $key and $value and !empty($attrs) {
    fail('You cannot specify $key/$value and $attrs together')
  }

  $_known_instances = pick($facts['ds389__instances'], {})

  $_root_dn = pick($root_dn, pick($_known_instances.dig($_instance_name, 'rootdn'), false))
  unless $_root_dn {
    fail("You must specify an \$root_dn for '${title}'")
  }

  $_root_pw_file = pick($root_pw_file, "/usr/share/puppet_ds389_config/${_instance_name}_ds_pw.txt")

  if $force_ldapi or $_known_instances.dig($_instance_name, 'ldapilisten') {
    $_ldapi_path = $_known_instances.dig($_instance_name, 'ldapifilepath')

    if $_ldapi_path {
      $_host_target = "ldapi://${_ldapi_path.regsubst('/','%2f', 'G')}"
    }
    else {
      $_host_target = "ldapi://%2fvar%2frun%2fslapd-${_instance_name}.socket"
    }
  }
  else {
    if !$host or ($host in ['0.0.0.0', '::']) {
      $_host = '127.0.0.1'
    }
    else {
      $_host = $host
    }

    $_port = pick($port, pick($_known_instances.dig($_instance_name, 'port'), 389))

    $_host_target = "ldap://${_host}:${_port}"
  }

  $_ldap_command_base = "-x -D '${_root_dn}' -y '${_root_pw_file}' -H ${_host_target}"

  ensure_resource('ds389::instance::service', $_instance_name)

  if !empty($attrs) {
    $_attrs = $attrs
  }
  else {
    $_attrs = {
      $base_dn => {
        $key => $value
      }
    }
  }

  $_attrs.each |String $_base_dn, Ds389::ConfigItem $_config_item| {
    $_config_item.each |String $_key, NotUndef $_value| {

      $_command = "echo -e \"dn: ${_base_dn}\\nchangetype: modify\\nreplace: ${_key}\\n${_key}: ${_value}\" | ldapmodify ${_ldap_command_base}"
      $_unless = "ldapsearch ${_ldap_command_base} -LLL -s base -S '' -a always -o ldif-wrap=no -b '${_base_dn}' '${_key}' | grep -x '${_key}: ${_value}'"

      # This should be a provider
      exec { "Set ${_base_dn},${_key} on ${_instance_name}":
        command => Sensitive($_command),
        unless  => Sensitive($_unless),
        path    => ['/bin', '/usr/bin'],
        require => Ds389::Instance::Service[$_instance_name]
      }

      if $restart_instance or
        $_key in lookup('ds389::config::attributes_requiring_restart', { 'default_value' => [] })
      {
        # Workaround for LDAPI bootstrapping
        if $force_ldapi {
          $_restart_title = "Restart LDAPI ${_instance_name}"
        }
        else {
          $_restart_title = "Restart ${_instance_name}"
        }

        ensure_resource('exec', $_restart_title, {
            command     => "/sbin/restart-dirsrv ${_instance_name}",
            refreshonly => true
          }
        )

        Exec["Set ${_base_dn},${_key} on ${_instance_name}"] ~> Exec[$_restart_title]
      }
    }
  }
}

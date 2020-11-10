# Modifies the running directory server configuration and restarts the service
# when necessary.
#
# @option name [String]
#   A unique description of the desired configuration setting
#
# @param key
#   The configuration key to be set
#
#     * You can get a list of all configuration keys by running:
#       ``ldapsearch -H ldap://localhost:389 \
#       -y /usr/share/puppet_ds389_config/<instance_name>_ds_pw.txt \
#       -D "cn=SIMP Directory Manager" -s base -b "cn=config"``
#
# @param value
#   The value that should be set for ``$key``
#
# @param admin_dn
#   A DN with administrative rights to the directory
#
# @param pw_file
#   A file containing the password for use with ``$admin_dn``
#
# @param service_name
#   The Puppet resource name for the directory ``Service`` resource
#
# @param restart_service
#   Whether or not to restart the directory server after applying this item
#
#     * There is a known list of items in the module data that will always
#       generate a restart action
#
# @param host
#   The host where the service is running
#
# @param port
#   The port to which to connect
#
# @param base_dn
#   The DN that holds the directory configuration items
#
# @param encrypt_connection
#   If set to `false`, do not require encryption for off-host connections.
#
#   * Loopback connections are never encrypted.
#
define ds389::config::item (
  String[1]                     $key,
  String[1]                     $value,
  String[2]                     $admin_dn,
  Stdlib::Absolutepath          $pw_file,
  Simplib::Systemd::ServiceName $service_name,
  Boolean                       $restart_service    = false,
  Simplib::Host                 $host               = '127.0.0.1',
  Simplib::Port                 $port               = 389,
  String[2]                     $base_dn            = 'cn=config',
  Boolean                       $encrypt_connection = true
) {

  if stdlib::start_with($service_name, 'dirsrv@') {
    $_service_name = $service_name
  }
  else {
    $_service_name = "dirsrv@${service_name}"
  }

  if $host in ['0.0.0.0', '::'] {
    $_host = '127.0.0.1'
  }
  else {
    $_host = $host
  }

  $_ldap_command_base = "-x -D '${admin_dn}' -y '${pw_file}' -H ldap://${_host}:${port}"

  if $_host in ['127.0.0.1', 'localhost', '::1'] {
    $_ldap_command_extra = ''
  }
  elsif $encrypt_connection {
    # Encrypt if going off system
    $_ldap_command_extra = '-ZZ'
  }

  $_command = "echo -e \"dn: ${base_dn}\\nchangetype: modify\\nreplace: ${key}\\n${key}: ${value}\" | ldapmodify ${_ldap_command_extra} ${_ldap_command_base}"
  $_unless = "test `ldapsearch ${_ldap_command_extra} ${_ldap_command_base} -LLL -s base -b '${base_dn}' '${key}' | grep -e '^${key}' | awk '{ print \$2 }'` == '${value}'"

  # This should be a provider
  exec { "Set ${base_dn},${key} on ${_service_name}":
    command => Sensitive($_command),
    unless  => Sensitive($_unless),
    path    => ['/bin', '/usr/bin']
  }

  if $restart_service or (
    $name in lookup('ds389::config::attributes_requiring_restart')
  ) {
    ensure_resource('service', $_service_name, {})

    Exec["Set ${base_dn},${key} on ${_service_name}"] ~> Service[$_service_name]
  }
}

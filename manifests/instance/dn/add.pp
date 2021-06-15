# Creates the passed DN using the provided paramters
#
# NOTE: When calling this defined type as you first set up an instance, you
# will need to pass in all parameters since the fact will not yet be fully
# populated.
#
# If passing a full LDIF - DO NOT WRAP LINES
#
# @option name [String]
#   A globally unique description of the desired configuration setting
#
# @param instance_name
#   The instance name as passed to `ds389::instance`
#
# @param dn
#   The DN to be created
#
# @param objectclass
#   objectClasses to which the DN belongs
#
# @param attrs
#   Attributes that you wish to set at the time of creation
#
# @param content
#   The full content of the LDIF
#
#   * This may only contain *one* entry
#   * All other parameters will be ignored
#   * DO NOT add 'changetype: add'
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
define ds389::instance::dn::add (
  Simplib::Systemd::ServiceName         $instance_name,
  Optional[Pattern['^\S+=.+']]          $dn               = undef,
  Optional[Array[String[1],1]]          $objectclass      = undef,
  Optional[Hash[String[1],String[1],1]] $attrs            = undef,
  Optional[String[3]]                   $content          = undef,
  Optional[String[2]]                   $root_dn          = undef,
  Optional[Stdlib::Absolutepath]        $root_pw_file     = undef,
  Optional[Simplib::Host]               $host             = undef,
  Optional[Simplib::Port]               $port             = undef,
  Boolean                               $force_ldapi      = false,
  Boolean                               $restart_instance = false
) {
  $_instance_name = split($instance_name, /^(dirsrv@)?slapd-/)[-1]
  $_filesafe_dn = regsubst($dn, '[\\\\/:~\n\s\+\*\(\)@]', '__', 'G')

  if !$dn and !content {
    fail('You must specify either $dn or $content')
  }
  if $dn and !($objectclass or $attrs) {
    fail('You must specify $objectclass and $attrs with $dn')
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

  if $content {
    $_ldif = $content
  }
  else {
    $_ldif = @("LDIF")
      dn: ${dn}
      ${dn.split(',')[0].split('=').join(': ')}
      ${objectclass.sort.map |$oc| { "objectClass: ${oc}"}.join("\n")}
      ${attrs.map |$k, $v| { "${k}: ${v}" }.join("\n")}
      | LDIF
  }

  $_ldif_file = "${ds389::ldif_working_dir}/${_instance_name}_add_${$_filesafe_dn}.ldif"

  file { $_ldif_file:
    owner   => 'root',
    group   => 'root',
    mode    => '0400',
    content => Sensitive($_ldif),
    notify  => Exec[$_ldif_file]
  }

  $_command = "ldapadd ${_ldap_command_base} -f '${_ldif_file}'"
  $_unless = "ldapsearch ${_ldap_command_base} -LLL -s base -S '' -o ldif-wrap=no -b '${dn}'"

  # This should be a provider
  exec { $_ldif_file:
    command => $_command,
    unless  => $_unless,
    path    => ['/bin', '/usr/bin'],
    require => Ds389::Instance::Service[$_instance_name]
  }

  if $restart_instance {
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

    Exec[$_ldif_file] ~> Exec[$_restart_title]
  }
}

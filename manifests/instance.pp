# @summary Set up a local 389DS server
#
# @param base_dn
#   The 'base' DN component of the directory server
#
# @param root_dn
#   The default administrator DN for the directory server
#
#   * NOTE: To work around certain application bugs, items with spaces may not
#     be used in this field.
#
# @param root_dn_password
#   The password for the the ``$root_dn``
#
#   * NOTE: To work around certain application bugs, items with spaces may not
#     be used in this field.
#
# @param listen_address
#   The IP address upon which to listen
#
# @param port
#   The port upon which to accept normal/STARTTLS connections
#
# @param secure_port
#   The port upon which to accept LDAPS connections
#
# @param service_user
#   The user that ``389ds`` should run as
#
# @param service_group
#   The group that ``389ds`` should run as
#
# @param bootstrap_ldif_content
#   The content that should be used to initialize the directory
#
# @param general_config
#   General configuration items for the instance
#
#   * These items fall under the `cn=config` root and will take precedence over
#     any conflicting, more specific, Hashes
#
# @param enable_tls
#   This will enable TLS and affect how the pki certs are configured.
#   'simp'     => enables TLS and copies the certs from the puppetserver
#                 using the SIMP pki module.
#   'true'     => enables TLS and copies the certs from a location on the
#                 local system. See pki module to see the required
#                 configuration of the directory.
#   'false'    => Do nothing with the TLS settings.
#   'disabled' => Disable TLS on the instance.
#
# @param tls_params
#   Parameters to pass to the TLS module:
#
# @example
#   Set up an instance where TLS is enabled and the certificates
#   are located in a directory called /my/local/certdir
#   ds389::instances { 'bestever':
#     base_dn => 'dc=best,dc=ever,dc=org',
#     root_dn => "cn=BestDirectoryManager",
#     listen_address => '0.0.0.0',
#     enable_tls => true,
#     tls_params => {
#       source => '/my/local/certdir'
#     }
#   }

# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance (
  Enum['present','absent']       $ensure                 = 'present',
  Optional[String[2]]            $base_dn                = undef,
  Optional[Pattern['^[\S]+$']]   $root_dn                = undef,
  Simplib::IP                    $listen_address         = '127.0.0.1',
  Simplib::Port                  $port                   = 389,
  Simplib::Port                  $secure_port            = 636,
  Optional[Pattern['^[\S]+$']]   $root_dn_password       = undef,
  String[1]                      $machine_name           = $facts['fqdn'],
  String[1]                      $service_user           = 'dirsrv',
  String[1]                      $service_group          = 'dirsrv',
  Optional[String[1]]            $bootstrap_ldif_content = undef,
  Optional[String[1]]            $ds_setup_ini_content   = undef,
  Ds389::ConfigItem              $general_config         = simplib::dlookup('ds389::instance', 'general_config', {'default_value' => {} }),
  Ds389::ConfigItem              $password_policy        = simplib::dlookup('ds389::instance', 'password_policy', {'default_value' => {} }),
  Variant[Boolean, Enum['simp']] $enable_tls             = simplib::lookup('simp_options::pki', { 'default_value' => false }),
  Hash                           $tls_params             = simplib::dlookup('ds389::instance', 'tls_params', { 'default_value' => {} }),
) {
  simplib::assert_metadata($module_name)

  assert_type(Simplib::Systemd::ServiceName, $title) |$expected, $actual| {
    fail("The \$title for ds389::instance must be a valid systemd service name matching ${expected}. Got ${actual}")
  }
  if stdlib::start_with($title, 'dirsrv@') or stdlib::start_with($title, 'slapd-') {
    fail('The $title for ds389::instance cannot start with "dirsrv@" or "slapd-"')
  }
  if $title == 'admin' {
    fail('The 389DS server does not allow instances named "admin"')
  }
  if stdlib::end_with($title, '.removed') {
    fail('You cannot end a 389DS instance with ".removed"')
  }

  $_ds_remove_command = "/sbin/remove-ds.pl -f -i slapd-${title}"

  if $ensure == 'present' {
    unless $base_dn { fail('You must specify a base_dn') }
    unless $root_dn { fail('You must specify a root_dn') }

    # Check to make sure we're not going to have a conflict with something that's running
    pick($facts['ds389__instances'], {}).each |$daemon, $data| {
      unless $daemon == $title {
        if ($data['port'] == $port) or ($data['securePort'] == $port) {
          fail("The port '${port}' is already in use by '${daemon}'")
        }
      }
    }

    if defined_with_params(Ds389::Instance, { 'ensure' => $ensure, 'port' => $port }) {
      fail("The port '${port}' is already selected for use by another defined catalog resource")
    }

    # We need to include this here to make sure that all of the top-level
    # parameters propagate correctly downwards
    include ds389

    $_safe_path = simplib::safe_filename($title)

    if $root_dn_password {
      $_root_dn_password = $root_dn_password
    }
    else {
      $_root_dn_password = simplib::passgen("389-ds-${_safe_path}", { 'length' => 64, 'complexity' => 0 })
    }

    if $ds_setup_ini_content {
      $_ds_setup_inf = $ds_setup_ini_content
    }
    else {
      if $bootstrap_ldif_content {
        $_bootstrap_ldif_file = "${ds389::config_dir}/${_safe_path}_ds_bootstrap.ldif"

        file { $_bootstrap_ldif_file:
          owner   => 'root',
          group   => $service_group,
          mode    => '0640',
          content => Sensitive($bootstrap_ldif_content)
        }

        unless $title in pick($facts['ds389__instances'], {}).keys {
          File[$_bootstrap_ldif_file] ~> Exec["Setup ${title} DS"]
        }
      }
      else {
        $_bootstrap_ldif_file = undef
      }

      $_ds_setup_inf = epp("${module_name}/instance/setup.ini.epp",
        {
          server_identifier   => $title,
          base_dn             => $base_dn,
          root_dn             => $root_dn,
          root_dn_password    => $_root_dn_password,
          service_user        => $service_user,
          service_group       => $service_group,
          machine_name        => $machine_name,
          port                => $port,
          bootstrap_ldif_file => $_bootstrap_ldif_file
        }
      )
    }

    ds389::instance::selinux::port { String($port):
      instance => $title,
      default  => 389
    }

    $_ds_config_file = "${ds389::config_dir}/${$_safe_path}_ds_setup.inf"

    file { $_ds_config_file:
      owner                   => 'root',
      group                   => 'root',
      mode                    => '0600',
      selinux_ignore_defaults => true,
      content                 => Sensitive($_ds_setup_inf),
      require                 => Class['ds389::install']
    }

    unless $title in pick($facts['ds389__instances'], {}).keys {
      File[$_ds_config_file] ~> Exec["Setup ${title} DS"]
    }

    $_ds_instance_setup = "/etc/dirsrv/slapd-${_safe_path}/.puppet_bootstrapped"
    #$_ds_instance_setup = "/etc/dirsrv/slapd-${_safe_path}/dse.ldif"

    if $title in pick($facts['ds389__instances'], {}).keys {
      exec { "Cleanup Bad Bootstrap for ${title} DS":
        command => "${ds389::install::remove_command} -i slapd-${title}",
        creates => $_ds_instance_setup,
        notify  => Exec["Setup ${title} DS"]
      }
    }

    exec { "Setup ${title} DS":
      command => "${ds389::install::setup_command} --silent -f ${_ds_config_file} && touch '${_ds_instance_setup}'",
      creates => $_ds_instance_setup,
      notify  => Ds389::Instance::Service[$title]
    }

    $_ds_pw_file = "${ds389::config_dir}/${_safe_path}_ds_pw.txt"

    file { $_ds_pw_file:
      ensure  => 'present',
      owner   => 'root',
      group   => 'root',
      mode    => '0400',
      content => Sensitive($_root_dn_password),
      require => Exec["Setup ${title} DS"]
    }

    ensure_resource('ds389::instance::service', $title)

    # This needs to happen first so that we can skip through to ldapi afterwards
    ds389::instance::attr::set { "Configure LDAPI for ${title}":
      instance_name    => $title,
      attrs            => {
        'cn=config'    => {
          'nsslapd-ldapilisten'   => 'on',
          'nsslapd-ldapiautobind' => 'on',
          'nsslapd-localssf'      => 99999
        }
      },
      root_dn          => $root_dn,
      root_pw_file     => $_ds_pw_file,
      host             => $listen_address,
      port             => $port,
      restart_instance => true
    }

    $_dse_config = {
      'cn=config' => {
        'nsslapd-listenhost'       => $listen_address,
        'nsslapd-securelistenhost' => $listen_address
      }.merge($general_config).merge($password_policy)
    }
    ds389::instance::attr::set { "Core configuration for ${title}":
      instance_name => $title,
      attrs         => $_dse_config,
      root_dn       => $root_dn,
      root_pw_file  => $_ds_pw_file,
      force_ldapi   => true,
      require       => Ds389::Instance::Attr::Set["Configure LDAPI for ${title}"]
    }

    if $enable_tls {
      ds389::instance::tls { $title:
        ensure        => $enable_tls,
        root_dn       => $root_dn,
        root_pw_file  => $_ds_pw_file,
        port          => $secure_port,
        service_group => $service_group,
        *             => $tls_params,
        require       => Ds389::Instance::Attr::Set["Configure LDAPI for ${title}"]
      }
    }
  }
  else {
    exec { "Remove 389DS instance ${title}":
      command => $_ds_remove_command,
      onlyif  => "/bin/test -d /etc/dirsrv/slapd-${title}"
    }

    pick($facts['ds389__instances'], {}).each |$daemon, $data| {
      if ($daemon == $title) {
        # It is only safe to remove the selinux ports if you know they are
        # in use for the 389ds instance
        if ( $data['port'] == $port) {
          ensure_resource('ds389::instance::selinux::port', String($port), {
              enable  => false,
              default => 389
            }
          )
        }

        if ( $data['securePort'] == $secure_port) {
          ensure_resource('ds389::instance::selinux::port', String($secure_port), {
              enable  => false,
              default => 636
            }
          )
        }
      }
    }
  }
}

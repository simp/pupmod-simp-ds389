# @summary Create a default instance with a common organizational LDIF
#
# @param base_dn
#   The 'base' DN component of the instance
#
# @param root_dn
#   The default administrator DN for the instance
#
# @param admin_password
#   The password for the ``$admin_user`` and the ``$root_dn``
#
# @param listen_address
#   The IP address upon which to listen
#
# @param port
#   The port upon which to accept connections
#
# @param enable_admin_service
#   Enable the administrative interface for the GUI
#
# @param admin_user
#   The administrative user for administrative GUI connections
#
# @param admin_service_listen_address
#   The IP address upon which the administrative interface should listen
#
# @param admin_service_port
#   The port upon which the administrative interface should listen
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
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
class ds389::instance::default (
  String[1]            $instance_name,
  Boolean              $bootstrap_with_defaults      = true,
  Optional[String[2]]  $base_dn                      = undef,
  Optional[String[2]]  $root_dn                      = undef,
  Simplib::IP          $listen_address               = '0.0.0.0',
  Simplib::Port        $port                         = 389,
  Boolean              $enable_admin_service         = false,
  String[2]            $admin_user                   = 'admin',
  Optional[String[2]]  $admin_password               = undef,
  Simplib::Domain      $admin_domain                 = $facts['domain'],
  Simplib::IP          $admin_service_listen_address = '127.0.0.1',
  Simplib::Port        $admin_service_port           = 9830,
  String[1]            $machine_name                 = $facts['fqdn'],
  String[1]            $service_user                 = 'nobody',
  String[1]            $service_group                = 'nobody',
  Optional[String[1]]  $bootstrap_ldif_content       = undef,
  Optional[String[1]]  $ds_setup_ini_content         = undef,
  Stdlib::Absolutepath $config_dir                   = '/usr/share/puppet_ds389_config',
  # Default LDIF configuration parameters
  Integer[1]           $users_group_id               = 100,
  Integer[500]         $administrators_group_id      = 700
) {
  assert_private()

  if $ds_setup_ini_content {
    $_ds_setup_ini_content = $ds_setup_ini_content
  }
  elsif $bootstrap_ldif_content {
    $_ds_setup_ini_content = undef
    $_bootstrap_ldif_content = $bootstrap_ldif_content
  }
  elsif $bootstrap_with_defaults {
    $_ds_setup_ini_content = undef
    $_bootstrap_ldif_content = epp("${module_name}/instance/bootstrap.ldif.epp",
      {
        base_dn                 => $base_dn,
        users_group_id          => $users_group_id,
        administrators_group_id => $administrators_group_id
      }
    )
  }
  else {
    $_ds_setup_ini_content = undef
    $_bootstrap_ldif_content = undef
  }

  ds389::instance { $instance_name:
    base_dn                      => $base_dn,
    root_dn                      => $root_dn,
    listen_address               => $listen_address,
    port                         => $port,
    enable_admin_service         => $enable_admin_service,
    admin_user                   => $admin_user,
    admin_password               => $admin_password,
    admin_domain                 => $admin_domain,
    admin_service_listen_address => $admin_service_listen_address,
    admin_service_port           => $admin_service_port,
    machine_name                 => $machine_name,
    service_user                 => $service_user,
    service_group                => $service_group,
    bootstrap_ldif_content       => $_bootstrap_ldif_content,
    ds_setup_ini_content         => $_ds_setup_ini_content,
    config_dir                   => $config_dir
  }
}

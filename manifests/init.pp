# @summary Set up a local 389DS server
#
# @param base_dn
#   The 'base' DN component of the directory server
#
# @param root_dn
#   The default administrator DN for the directory server
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
# @param package_ensure
#   What to do regarding package installation
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
class ds389 (
  Boolean                $initialize_ds_root           = false,
  Boolean                $bootstrap_ds_root_defaults   = true,
  String[1]              $ds_root_name                 = 'puppet_default_root',
  String[2]              $base_dn                      = simplib::lookup('simp_options::ldap::base_dn', { 'default_value' => sprintf(simplib::ldap::domain_to_dn($facts['domain'], true)) }),
  String[2]              $root_dn                      = 'cn=Directory Manager',
  Simplib::IP            $listen_address               = '0.0.0.0',
  Simplib::Port          $port                         = 389,
  Boolean                $enable_admin_service         = false,
  String[2]              $admin_user                   = 'admin',
  Optional[String[2]]    $admin_password               = undef,
  Simplib::IP            $admin_service_listen_address = '0.0.0.0',
  Simplib::Port          $admin_service_port           = 9830,
  String[1]              $service_user                 = 'nobody',
  String[1]              $service_group                = 'nobody',
  Hash                   $instances                    = {},
  Simplib::PackageEnsure $package_ensure               = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })
) {
  include ds389::install

  if $initialize_ds_root {
    class { 'ds389::instance::default':
      instance_name                => $ds_root_name,
      bootstrap_with_defaults      => $bootstrap_ds_root_defaults,
      base_dn                      => $base_dn,
      root_dn                      => $root_dn,
      listen_address               => $listen_address,
      port                         => $port,
      enable_admin_service         => $enable_admin_service,
      admin_user                   => $admin_user,
      admin_password               => $admin_password,
      admin_service_listen_address => $admin_service_listen_address,
      admin_service_port           => $admin_service_port,
      service_user                 => $service_user,
      service_group                => $service_group
    }
  }

  $instances.each |$id, $options| {
    ds389::instance { $id:
      * => $options
    }
  }
}

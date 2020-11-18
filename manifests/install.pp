# @summary Set up a local 389DS server
#
# @param package_list
#   A list of packages that will installed instead of the internally selected
#   packages.
#
# @param setup_command
#   The path to the setup command on the system
#
# @param admin_setup_command
#   The path to the admin setup command on the system
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
class ds389::install (
  Boolean                    $enable_admin_service = pick(getvar('ds389::enable_admin_service'), false),
  Optional[Array[String[1]]] $package_list         = undef,
  Optional[Array[String[1]]] $admin_package_list   = undef,
  Optional[String[1]]        $dnf_module           = undef,
  Optional[String[1]]        $dnf_stream           = undef,
  Optional[String[1]]        $dnf_profile          = undef,
  Stdlib::Unixpath           $setup_command        = '/sbin/setup-ds.pl',
  Stdlib::Unixpath           $admin_setup_command  = '/sbin/setup-ds-admin.pl'
) {
  assert_private()

  unless $package_list or $dnf_module {
    fail('You must specify either "$package_list" or "$dnf_module"')
  }

  if $dnf_module and ( $facts['package_provider'] == 'dnf' ) {
    package { $dnf_module:
      ensure   => $dnf_stream,
      flavor   => $dnf_profile,
      provider => 'dnfmodule'
    }
  }

  if $package_list and !empty($package_list) {
    if $admin_package_list and $enable_admin_service {
      $_389_packages = $admin_package_list
    }
    else {
      $_389_packages = $package_list
    }

    ensure_packages($_389_packages, { ensure => $ds389::package_ensure })
  }
}

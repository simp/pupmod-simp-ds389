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
  Boolean          $enable_admin_service = pick(getvar('ds389::enable_admin_service'), false),
  Array[String]    $package_list        = ['389-ds-base'],
  Array[String]    $admin_package_list  = ['389-admin', '389-admin-console', '389-ds-console'],
  Stdlib::Unixpath $setup_command       = '/sbin/setup-ds.pl',
  Stdlib::Unixpath $admin_setup_command = '/sbin/setup-ds-admin.pl'
) {
  assert_private()

  if $enable_admin_service {
    $_389_packages = $admin_package_list
  }
  else {
    $_389_packages = $package_list
  }

  ensure_packages($_389_packages, { ensure => $ds389::package_ensure })
}

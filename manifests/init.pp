# @summary Set up a local 389DS server
#
# @param service_group
#   The group DS389 is installed under.
#
# @param ldif_working_dir
#   A directory used for temporary storage of ldifs during
#   configuration.
#
# @param instances
#   A hash of instances to be created when the server is installed.
#
# @param package_ensure
#   What to do regarding package installation
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
class ds389 (
  Stdlib::Absolutepath         $config_dir                   = '/usr/share/puppet_ds389_config',
  Stdlib::Absolutepath         $ldif_working_dir             = "${config_dir}/ldifs",
  String[1]                    $service_group                = 'dirsrv',
  Hash                         $instances                    = {},
  Simplib::PackageEnsure       $package_ensure               = simplib::lookup('simp_options::package_ensure', { 'default_value' => 'installed' })
) {
  # WARNING: This is included by several defined types.
  # DO NOT add items here that will apply without being disabled by default.

  include ds389::install

  file {
    [
      $config_dir,
      $ldif_working_dir
    ]:
    ensure  => 'directory',
    owner   => 'root',
    group   => $service_group,
    mode    => 'u+rwx,g+x,o-rwx',
    purge   => true,
    recurse => true
  }

  file { "$config_dir/ca_import.sh":
    ensure  => 'file',
    owner   => 'root',
    group   => 'root',
    mode    => '0700',
    content => epp("${module_name}/ca_import.sh.epp")
  }

  $instances.each |$id, $options| {
    ds389::instance { $id:
      * => $options
    }

    File[$ldif_working_dir] -> Ds389::Instance[$id]
  }
}

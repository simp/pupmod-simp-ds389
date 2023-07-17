# @summary Consolidate selinux_port enable/disable logic
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance::selinux::port (
  Simplib::Port       $default,
  Optional[String[1]] $instance = undef,
  Boolean             $enable   = true
) {
  assert_private()

  $_port = Integer($title)

  if ($_port != $default) and $facts['os']['selinux']['enforced'] {
    if simplib::module_exist('simp/selinux') {
      simplib::assert_optional_dependency($module_name, 'simp/selinux')
      simplib::assert_optional_dependency($module_name, 'simp/vox_selinux')

      include selinux::install
    }
    else {
      simplib::assert_optional_dependency($module_name, 'puppet/selinux')
    }

    $_ensure = $enable ? {
      true  => 'present',
      false => 'absent'
    }

    selinux_port { "tcp_${_port}-${_port}":
      ensure    => $_ensure,
      low_port  => $_port,
      high_port => $_port,
      seltype   => 'ldap_port_t',
      protocol  => 'tcp'
    }

    if $instance {
      Selinux_port["tcp_${_port}-${_port}"] -> Exec["Setup ${instance} DS"]
      Selinux_port["tcp_${_port}-${_port}"] -> Ds389::Instance::Service[$instance]
    }
  }
}

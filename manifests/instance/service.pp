# @summary Configure an instance service
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance::service (
  Enum['stopped','running'] $ensure     = simplib::dlookup('ds389::instance::service', 'ensure', $name, { 'default_value' => 'running'}),
  Boolean                   $enable     = simplib::dlookup('ds389::instance::service', 'enable', $name, { 'default_value' => true}),
  Boolean                   $hasrestart = simplib::dlookup('ds389::instance::service', 'hasrestart', $name, { 'default_value' => true})
) {
  assert_private()

  $_instance_name = split($title, /^(dirsrv@)?slapd-/)[-1]

  # Ensure that services start at boot time
  ensure_resource('service', 'dirsrv.target', { enable => true })

  ensure_resource('service', "dirsrv@${_instance_name}",
    {
      ensure     => $ensure,
      enable     => $enable,
      hasrestart => $hasrestart
    }
  )
}

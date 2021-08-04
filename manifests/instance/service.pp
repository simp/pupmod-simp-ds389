# @summary Configure an instance service
#
# @author https://github.com/simp/pupmod-simp-ds389/graphs/contributors
#
define ds389::instance::service (
  Enum['stopped','running'] $ensure     = simplib::dlookup('ds389::instance::service', 'ensure', $name, { 'default_value' => 'running'}),
  Boolean                   $enable     = simplib::dlookup('ds389::instance::service', 'enable', $name, { 'default_value' => true}),
  Boolean                   $hasrestart = simplib::dlookup('ds389::instance::service', 'hasrestart', $name, { 'default_value' => true})
){
  assert_private()

  $_instance_name = split($title, /^(dirsrv@)?slapd-/)[-1]

  # Ensure that services start at boot time
  ensure_resource('service', 'dirsrv.target', { enable => true })

  $_loglevel_override = @(OVERRIDE)
    [Service]
    LogLevelMax=warning
    | OVERRIDE

  ensure_resource('systemd::dropin_file', "00_dirsrv_${_instance_name}_loglevel.conf", {
    unit    => "dirsrv@${_instance_name}.service",
    content => $_loglevel_override
  })

  ensure_resource('service', "dirsrv@${_instance_name}", {
    ensure     => $ensure,
    enable     => $enable,
    hasrestart => $hasrestart,
    require    => Systemd::Dropin_file["00_dirsrv_${_instance_name}_loglevel.conf"]
  })
}

# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## What this module does

`simp-ds389` is a SIMP Puppet module that manages **389 Directory Server**
(389DS / `dirsrv`) LDAP instances on Enterprise Linux systems. It installs the
389DS packages and then creates and configures one or more directory-server
*instances* declaratively. For each instance it: renders a `dscreate` setup
`.inf` file and runs `dscreate from-file` to build the instance; optionally
imports a bootstrap LDIF; opens the required SELinux ports; manages the systemd
service (with a log-level drop-in); pushes runtime `cn=config` attributes over
LDAPI/LDAP using `dsconf`; and optionally configures TLS (certificate import
into the NSS DB plus encryption attributes).

The design is **fact-driven and idempotent**. A custom fact `ds389__instances`
reads `/etc/dirsrv/slapd-*/dse.ldif` to discover the instances that already
exist, and the manifests branch their behavior (skip re-setup, port-conflict
checks, LDAPI vs LDAP targeting, restart-vs-not) off that fact plus a per-
instance `/etc/dirsrv/slapd-<name>/.puppet_bootstrapped` marker file. The
entry class `ds389` is `include`d by the defines, so `ds389::instance { ... }`
can be declared directly without first classifying `ds389`.

## Business logic

### `class ds389` (`manifests/init.pp`)

Public entry class (not `assert_private()`'d). Parameters: `$config_dir`
(`Stdlib::Absolutepath`, default `/usr/share/puppet_ds389_config`),
`$ldif_working_dir` (default `${config_dir}/ldifs`), `$service_group`
(`String[1]`, default `dirsrv`), `$instances` (`Hash`, default `{}`),
`$package_ensure` (`String`, default `installed`).

- **The class is deliberately kept inert.** An explicit warning
  (`init.pp`) says it is included by several defined types, so do **not**
  add resources here that apply without being disabled by default.
- `include ds389::install` (`init.pp`).
- Creates `$config_dir` and `$ldif_working_dir` as directories, `owner root`,
  `group $service_group`, mode `u+rwx,g+x,o-rwx`, with **`purge => true,
  recurse => true`** (`init.pp`) — Puppet will delete unmanaged files in
  those directories.
- Creates `${config_dir}/ca_import.sh` mode `0700` from the `ca_import.sh.epp`
  template (`init.pp`).
- Iterates `$instances`, declaring a `ds389::instance` per entry
  (`init.pp`).

### `class ds389::install` (`manifests/install.pp`)

`assert_private()` (`install.pp`). Installs the 389DS packages two ways and
**fails unless `$package_list` or `$dnf_module` is set** (`install.pp`):

- `$dnf_module` path (EL8): declares a `package` with `provider => 'dnfmodule'`,
  `ensure => $dnf_stream`, `enable_only => $dnf_enable_only`, `flavor =>
  $dnf_profile` (`install.pp`). Selected via module data on EL8.
- `$package_list` path (EL9/10): `stdlib::ensure_packages($package_list, {
  'ensure' => $ds389::package_ensure })` (`install.pp`).

Also holds the command paths used by the instance defines: `$setup_command`
(`/usr/sbin/dscreate`), `$remove_command` (`/usr/sbin/dsctl`), `$dsconf_command`
(`/usr/sbin/dsconf`).

### `define ds389::instance` (`manifests/instance.pp`)

Public define — the primary interface. Builds/removes a single 389DS instance
keyed on `$title`. Key parameters: `$ensure` (`Enum['present','absent']`,
default `present`), `$base_dn`, `$root_dn`, `$listen_address`
(`Stdlib::IP::Address`, default `127.0.0.1`), `$port` (default `389`),
`$secure_port` (default `636`), `$root_dn_password`, `$machine_name` (default
FQDN), `$bootstrap_ldif_content`, `$ds_setup_ini_content`, `$general_config`
(`Ds389::ConfigItem`, default `nsslapd-dynamic-plugins=on` /
`nsslapd-allow-unauthenticated-binds=off` / `nsslapd-nagle=off`),
`$password_policy` (dlookup), `$enable_tls` (`Variant[Boolean, Enum['simp']]`,
default `false`), `$self_sign_cert` (`Enum['True','False']`, default `'False'`),
`$tls_params` (dlookup).

- **Strict title validation** (`instance.pp`): `$title` must match a
  systemd-safe pattern, must **not** start with `dirsrv@` or `slapd-`, must not
  be `admin`, and must not end with `.removed`.
- `include ds389` (`instance.pp`) to propagate the top-level params.
- **`ensure => present`** (`instance.pp`):
  - Requires `$base_dn` and `$root_dn` (`126-127`).
  - **Port-conflict checks**: against the `ds389__instances` fact
    (`130-136`) and against other `Ds389::Instance` resources in the catalog via
    `defined_with_params` (`138-140`).
  - Generates the root DN password when none is given:
    `simplib::passgen("389-ds-${safe}", { 'length' => 64, 'complexity' => 0 })`
    (`instance.pp`); `$safe = simplib::safe_filename($title)` (`142`).
  - Renders the `dscreate` setup INF from `setup.ini.epp` (or uses
    `$ds_setup_ini_content`); optionally writes a bootstrap LDIF (mode `0640`,
    `Sensitive`) first (`151-185`). Writes the INF to
    `${config_dir}/${safe}_ds_setup.inf` mode `0600`,
    `selinux_ignore_defaults => true`, content `Sensitive(...)` (`194-201`).
  - Opens the SELinux port via `ds389::instance::selinux::port` (`187-190`).
  - **Marker-driven bootstrap**: if the instance already exists in the fact but
    the `.puppet_bootstrapped` marker is missing, an `exec` first removes the
    bad instance (`209-215`). The main `exec "Setup <title> DS"` runs
    `dscreate from-file` (optionally `&& dsconf ... backend import userroot
    <ldif>`) and `touch`es the marker, with `creates => <marker>`
    (`217-228`).
  - Writes the password file `${config_dir}/${safe}_ds_pw.txt` mode `0400`
    (`Sensitive`) (`230-238`); ensures `ds389::instance::service` (`240`).
  - **Two `ds389::instance::attr::set` passes**: first "Configure LDAPI" sets
    `nsslapd-ldapilisten=on`, `nsslapd-ldapiautobind=on`,
    `nsslapd-localssf=99999` (so local operations count as high-security) with
    `restart_instance=true` (`243-255`); then "Core configuration" merges
    `nsslapd-listenhost`/`nsslapd-securelistenhost` with `$general_config` and
    `$password_policy`, `force_ldapi=true` (`257-269`).
  - If `$enable_tls`, declares `ds389::instance::tls { $title }` (`271-281`).
- **`ensure => absent`** (`instance.pp`): runs the `dsctl ... remove`
  command (guarded by `onlyif`) and disables the SELinux ports.

### `define ds389::instance::attr::set` (`manifests/instance/attr/set.pp`)

Public define — used directly to tweak `cn=config` attributes. Takes either a
single `$key`/`$value` or an `$attrs` hash (mutually exclusive). Targets the
instance over **LDAPI** (`ldapi://…` socket URI, built when `$force_ldapi` or
the fact shows `ldapilisten`) or **LDAP** (`ldap://host:port`, mapping
`0.0.0.0`/`::` to `127.0.0.1`). For each attribute it runs `dsconf ... config
replace key=value` guarded by an `unless` `dsconf ... config get | grep`
(`142-150`). Restarts the instance (`dsctl <name> restart`, `refreshonly`) when
`$restart_instance` is true **or** the key is in
`lookup('ds389::config::attributes_requiring_restart', …)` (`152-169`).
A `# This should be a provider` comment (`set.pp`) marks this exec approach
as acknowledged tech debt.

### `define ds389::instance::service` (`manifests/instance/service.pp`)

`assert_private()` (`service.pp`). Ensures the `dirsrv.target`, installs a
systemd drop-in `00_dirsrv_<name>_loglevel.conf` setting `LogLevelMax=warning`,
and manages the `dirsrv@<name>` service. `$ensure`/`$enable`/`$hasrestart` all
come from `simplib::dlookup` (per-`$name`).

### `define ds389::instance::selinux::port` (`manifests/instance/selinux/port.pp`)

`assert_private()` (`port.pp`). Declares `selinux_port { "tcp_<p>-<p>":
seltype => 'ldap_port_t' }` **only** when the port differs from the `$default`
(389) **and** SELinux is enforcing (`port.pp`).

### `define ds389::instance::tls` (`manifests/instance/tls.pp`)

`assert_private()` (`tls.pp`). Configures TLS for an instance: enforces
`nsslapd-security=on`, `nsslapd-securePort`, and (by default)
`nsslapd-minssf=128`, `nsslapd-SSLclientAuth=allowed`,
`nsslapd-ssl-check-hostname=on`, `nsslapd-validate-cert=on`. Manages the NSS
token via the custom `ds389_nss_token` type, optionally copies certs with
`pki::copy` (when `$ensure` is truthy/`'simp'`), builds/imports a `Server-Cert`
PKCS#12, and imports CAs via `ca_import.sh`. The `'disabled'` mode drops
`nsslapd-minssf` to `0` and disables the SELinux port.

## Custom code (`lib/`, `types/`)

- **`lib/facter/ds389__instances.rb`** — custom fact. `confine`d to `/etc/dirsrv`
  existing; globs `slapd-*` (skipping `*.removed`), parses each `dse.ldif`'s
  `cn=config` for a small set of attributes (ldapifilepath, ldapilisten,
  listenhost, port, require-secure-binds, rootdn, securePort), normalizes
  on/off→bool and numeric→int, and resolves `ldapilisten` to whether the socket
  file actually exists. This fact drives the module's idempotency; in a fresh
  compile / rspec it is empty, so tests must stub it.
- **`lib/puppet/type/ds389_nss_token.rb`** + **`lib/puppet/provider/ds389_nss_token/ruby.rb`**
  — custom type/provider (single underscore) managing an instance's NSS DB token
  files (`token.txt`, `pin.txt`) and running `modutil -changepw` when the token
  changes.
- **`types/configitem.pp`** — `Ds389::ConfigItem = Hash[String[1],
  Variant[Boolean, Integer[0], Float[0], String[1], Array[String[1], 1]]]`, the
  type for `cn=config` attribute maps.

## Templates (`templates/`, all EPP)

- **`ca_import.sh.epp`** — a **static** bash script (no EPP interpolation despite
  the extension) that diffs CA fingerprints in an NSS SQL DB and imports missing
  CAs via `certutil`; a `-c` compare-only mode exits `2` when an update is
  needed (used as an `onlyif` in `tls.pp`).
- **`instance/setup.ini.epp`** — renders the `dscreate` INF
  (`[general]`/`[slapd]`/`[backend-userroot]`); adds
  `self_sign_cert_valid_months=24` only when `$self_sign_cert == 'True'`.
- **`instance/bootstrap.ldif.epp`** — a full default directory tree (OUs, groups,
  password policies, ACIs). **Orphaned from manifest use** — it is available for
  callers to render into `$bootstrap_ldif_content`, not referenced automatically.

## Configuration seam (Hiera / `simplib::dlookup`)

**This module has no `simp_options::*` seam** — there are no `simp_options`
references in `manifests/`, `data/`, or `hiera.yaml`, and `simp/simp_options` is
**not** a dependency. The configuration seam is instead `simplib::dlookup`
(per-instance-aware lookups) plus one plain `lookup`:

| file:line | key | default |
|---|---|---|
| `instance.pp` | `ds389::instance` / `password_policy` | `{}` |
| `instance.pp` | `ds389::instance` / `tls_params` | `{}` |
| `instance/tls.pp` | `ds389::instance::tls` / `dse_config` | `{}` |
| `instance/service.pp` | `ds389::instance::service` / `ensure` (per `$name`) | `'running'` |
| `instance/service.pp` | `ds389::instance::service` / `enable` (per `$name`) | `true` |
| `instance/service.pp` | `ds389::instance::service` / `hasrestart` (per `$name`) | `true` |
| `instance/attr/set.pp` | `ds389::config::attributes_requiring_restart` | `[]` |

`data/common.yaml` sets deep-merge `lookup_options` (knockout prefix `--`) for
the config hashes and package list, and ships the
`ds389::config::attributes_requiring_restart` list. Per-OS data
(`data/os/*.yaml`) selects `ds389::install::package_list` (EL9/10) or the
`dnf_module`/`dnf_stream`/`dnf_enable_only` trio (EL8).

## Gotchas / non-obvious details

- **`ds389` is inert by design** (`init.pp`) — don't add always-on
  resources to it; it's a shared include.
- **`purge => true, recurse => true`** on `$config_dir`/`$ldif_working_dir`
  (`init.pp`) deletes unmanaged files placed there.
- **Everything hinges on the `ds389__instances` fact** and the
  `.puppet_bootstrapped` marker. Tests must stub the fact (it's empty on a fresh
  compile). The `attr::set` header notes you must pass all params on first setup
  because the fact isn't populated yet.
- **Secrets on disk**: the generated root DN password lands in
  `_ds_pw.txt` (mode `0400`) and the setup `.inf` (mode `0600`), both wrapped in
  `Sensitive()`. `passgen` uses `length => 64, complexity => 0`.
- **`self_sign_cert` is a string Enum `'True'`/`'False'`**, not a Boolean — it is
  written straight into the setup INI.
- **`nsslapd-localssf` is set to `99999`** during LDAPI bootstrap so local
  operations are treated as high-security (`instance.pp`).
- **TLS security posture**: `nsslapd-security=on`, `nsslapd-minssf=128`,
  `nsslapd-require-secure-binds=on` (from `data/common.yaml`) by default; the
  `'disabled'` TLS mode drops `minssf` to `0`.
- **`simp/pki`, `simp/selinux`, `simp/vox_selinux`, `puppet/selinux` are
  optional dependencies**, not hard deps — the TLS/SELinux paths degrade or are
  gated accordingly.
- **`ca_import.sh.epp` contains no EPP tags**, and **`bootstrap.ldif.epp` is not
  wired into any manifest** — both are easy to misread.

## Dependencies

Module dependencies (from `metadata.json`):

- `puppet/systemd` `>= 4.0.2 < 10.0.0`
- `simp/simplib` `>= 4.9.0 < 5.0.0` (provides `simplib::dlookup`,
  `simplib::passgen`, `simplib::safe_filename`)
- `puppetlabs/stdlib` `>= 8.0.0 < 10.0.0`

Optional dependencies (from `metadata.json` `simp.optional_dependencies`):

- `simp/pki` `>= 6.2.0 < 7.0.0`
- `simp/selinux` `>= 2.6.1 < 4.0.0`
- `simp/vox_selinux` `>= 3.1.0 < 4.0.0`
- `puppet/selinux` `>= 1.6.1 < 6.0.0`

Fixture-only dependencies (from `.fixtures.yml`, present for test compilation,
not runtime deps): `augeas_core`, `auditd`, `augeasproviders_core`,
`augeasproviders_grub`, `concat`, `augeasproviders_ssh`, `ssh` (plus the runtime
and optional deps above, also checked out as fixtures; `vox_selinux` is pinned to
the `simp-master` branch).

Runtime requirement (from `metadata.json` `requirements`): `puppet
>= 7.0.0 < 9.0.0`. (SIMP is migrating Puppet → OpenVox; when
`metadata.json` switches this to `openvox`, update this line to match.)

Supported OS matrix (from `metadata.json`): CentOS 9/10; OracleLinux 8/9/10;
RedHat 8/9/10; Rocky 8/9/10; AlmaLinux 8/9/10.

## Repository layout

- `manifests/init.pp` — `ds389` entry class (inert; dirs + `ca_import.sh` +
  instance iteration).
- `manifests/install.pp` — `ds389::install` (package install; EL8 dnfmodule vs
  EL9/10 package list; command paths).
- `manifests/instance.pp` — `ds389::instance`, the primary public define.
- `manifests/instance/attr/set.pp` — `ds389::instance::attr::set` (public;
  `dsconf` config replace).
- `manifests/instance/service.pp` — `ds389::instance::service` (private).
- `manifests/instance/selinux/port.pp` — `ds389::instance::selinux::port`
  (private).
- `manifests/instance/tls.pp` — `ds389::instance::tls` (private).
- `lib/facter/ds389__instances.rb` — instance-discovery fact.
- `lib/puppet/type/ds389_nss_token.rb`, `lib/puppet/provider/ds389_nss_token/ruby.rb`
  — NSS token type/provider.
- `types/configitem.pp` — `Ds389::ConfigItem` data type.
- `templates/` — `ca_import.sh.epp`, `instance/setup.ini.epp`,
  `instance/bootstrap.ldif.epp`.
- `data/` + `hiera.yaml` — module data (v5): OS+Release → OS → common; per-OS
  package selection + `lookup_options` deep-merge knockout + restart-attribute
  list.
- `metadata.json` — deps, optional deps, OS matrix, Puppet requirement.
- `spec/classes/` (init, install), `spec/defines/` (instance +
  instance/service, instance/tls, instance/attr/set), `spec/unit/puppet/`
  (ds389_nss_token type/provider), `spec/acceptance/` (suites/default with
  `00_default_spec.rb` + `10_pki_spec.rb`, plus nodesets). No `spec/functions/`.
- `REFERENCE.md` — generated Puppet Strings reference.
- **Acceptance runs in CI:** `.github/workflows/pr_tests.yml` has an
  `acceptance` job (matrix `almalinux9`, `almalinux10`) whose final step runs
  `bundle exec rake beaker:suites[default,<node>]` under
  `BEAKER_HYPERVISOR=vagrant_libvirt`.

## Common commands

```sh
# Install dependencies
bundle install

# Run all unit tests
bundle exec rake spec

# Run a single spec file
bundle exec rspec spec/defines/instance_spec.rb

# Puppet lint
bundle exec rake lint

# Ruby lint
bundle exec rake rubocop

# Regenerate REFERENCE.md from puppet-strings docstrings
puppet strings generate --format markdown --out REFERENCE.md

# Run the default beaker acceptance suite
bundle exec rake beaker:suites[default]
```

Relevant gem pins (from `Gemfile`): `puppetlabs_spec_helper ~> 8.0.0`,
`simp-rake-helpers ~> 5.24.0`, `simp-rspec-puppet-facts ~> 4.0.0`,
`simp-beaker-helpers ~> 2.0.0`. Rubocop is pinned to `~> 1.88.0`. The tested
Puppet range is `>= 7 < 9`.

## Conventions

- Preserve the `@summary` / `@param` / `@api private` puppet-strings docstrings
  on classes and defines — they drive `REFERENCE.md`. Regenerate `REFERENCE.md`
  after changing docs or parameters.
- Route configuration through `simplib::dlookup` (instance-aware) with an
  explicit `default_value`, and keep the deep-merge `lookup_options` (knockout
  `--`) in `data/common.yaml` in sync when adding new config hashes.
- Keep package selection in module data (`data/os/*.yaml`) — EL8 uses the DNF
  module stream, EL9/10 use `package_list`.
- Guard optional integrations (`pki`, `selinux`) as the existing code does; they
  are optional dependencies, not hard requirements.
- `Gemfile`, `spec/spec_helper.rb`, and `.github/workflows/pr_tests.yml` carry a
  **puppetsync** notice — they are baseline-managed and the next sync overwrites
  local edits. Push changes to those files upstream to the baseline, not here.
- Match the existing 2-space Puppet indentation and aligned-arrow parameter
  style used throughout `manifests/`.

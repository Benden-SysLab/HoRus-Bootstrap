# Pure LXC guest-baseline library. Loading this file performs no operations.
Set-StrictMode -Version Latest

function Assert-HorusLxcGuestBaselineSpec([System.Collections.IDictionary] $Spec) {
  foreach ($key in @('vmid', 'hostname', 'template_vmid', 'target_node', 'template_host_key_sha256', 'timezone')) {
    if (-not $Spec.Contains($key)) { throw "Missing guest-baseline field: $key" }
  }
  if ([int]$Spec.vmid -lt 100 -or [int]$Spec.vmid -ge 9000 -or [int]$Spec.template_vmid -ne 9001) {
    throw 'Only workload clones of external Golden LXC 9001 are supported.'
  }
  if ($Spec.target_node -notmatch '^horus-pmx-node0[1-4]$' -or $Spec.hostname -notmatch '^[a-z0-9-]+$') {
    throw 'Unsafe LXC identity or target node.'
  }
  if ($Spec.timezone -ne 'Europe/Moscow') {
    throw 'The approved HoRus LXC timezone is Europe/Moscow.'
  }
  if ($Spec.template_host_key_sha256 -notmatch '^SHA256:[A-Za-z0-9+/=]+$') {
    throw 'Golden LXC ED25519 fingerprint must use OpenSSH SHA256 format.'
  }
}

function Invoke-HorusLxcGuestBaselineCommand([object] $Context, [string] $Node, [string] $Command) {
  if ($Node -notmatch '^horus-pmx-node0[1-4]$') { throw "Unapproved node: $Node" }
  return (& $Context.Remote $Node $Command)
}

function Get-HorusLxcGuestBaselineGuest([object] $Context) {
  $raw = Invoke-HorusLxcGuestBaselineCommand $Context $Context.Spec.target_node 'pvesh get /cluster/resources --type vm --output-format json'
  $guests = @($raw | ConvertFrom-Json -AsHashtable | Where-Object { [int]$_.vmid -eq [int]$Context.Spec.vmid })
  if ($guests.Count -ne 1) { throw 'Expected exactly one LXC with the requested VMID.' }
  $guest = $guests[0]
  if ($guest.type -ne 'lxc' -or $guest.name -ne $Context.Spec.hostname -or ($guest.Contains('template') -and $guest.template)) {
    throw "VMID $($Context.Spec.vmid) identity mismatch; refusing guest-baseline changes."
  }
  if ($guest.node -ne $Context.Spec.target_node) { throw 'LXC is not on its Terraform target node.' }
  if ($guest.status -notin @('running', 'stopped')) { throw "Unsupported LXC status: $($guest.status)" }
  return $guest
}

function Get-HorusLxcGuestBaselineScript([string] $Root = '') {
  $prefix = if ($Root) { $Root } else { '' }
  return @"
set -eu
root='$prefix'
zone='Europe/Moscow'
zonefile="`$root/usr/share/zoneinfo/`$zone"
test -f "`$zonefile"
ln -snf "/usr/share/zoneinfo/`$zone" "`$root/etc/localtime"
tz_tmp="`$(mktemp "`$root/etc/.timezone.XXXXXX")"
printf '%s\n' "`$zone" > "`$tz_tmp"
chown --reference="`$root/etc/hostname" "`$tz_tmp"
chmod 0644 "`$tz_tmp"
mv -f "`$tz_tmp" "`$root/etc/timezone"
grep -q '^jenkins-srv:' "`$root/etc/passwd"
mkdir -p "`$root/etc/sudoers.d"
tmp="`$(mktemp "`$root/etc/sudoers.d/.jenkins-srv.XXXXXX")"
trap 'rm -f "`$tmp"' EXIT
printf '%s\n' 'jenkins-srv ALL=(ALL:ALL) NOPASSWD: ALL' > "`$tmp"
chown --reference="`$root/etc/sudoers" "`$tmp"
chmod 0440 "`$tmp"
visudo -cf "`$tmp" >/dev/null
mv -f "`$tmp" "`$root/etc/sudoers.d/jenkins-srv"
trap - EXIT
test "`$(readlink "`$root/etc/localtime")" = "/usr/share/zoneinfo/`$zone"
test "`$(cat "`$root/etc/timezone")" = "`$zone"
test "`$(stat -c %u:%g "`$root/etc/sudoers.d/jenkins-srv")" = "`$(stat -c %u:%g "`$root/etc/sudoers")"
test "`$(stat -c %a "`$root/etc/sudoers.d/jenkins-srv")" = '440'
test "`$(cat "`$root/etc/sudoers.d/jenkins-srv")" = 'jenkins-srv ALL=(ALL:ALL) NOPASSWD: ALL'
"@
}

function Get-HorusLxcSshFingerprintFromOutput([string] $Output) {
  if ($Output -match '(?m)\b(SHA256:[A-Za-z0-9+/=]+)\b') { return $Matches[1] }
  if ($Output -match '(?m)^MISSING\s*$') { return $null }
  throw 'Unable to parse LXC ED25519 host-key fingerprint.'
}

function Get-HorusLxcSshFingerprint([object] $Context, [System.Collections.IDictionary] $Guest) {
  $vmid = [int]$Context.Spec.vmid
  if ($Guest.status -eq 'running') {
    $command = "pct exec $vmid -- sh -c 'if test -f /etc/ssh/ssh_host_ed25519_key.pub; then ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256; else echo MISSING; fi'"
  } else {
    $root = "/var/lib/lxc/$vmid/rootfs"
    $command = "sh -ceu 'pct mount $vmid >/dev/null; trap `"pct unmount $vmid >/dev/null 2>&1 || true`" EXIT; if test -f $root/etc/ssh/ssh_host_ed25519_key.pub; then ssh-keygen -lf $root/etc/ssh/ssh_host_ed25519_key.pub -E sha256; else echo MISSING; fi'"
  }
  $raw = Invoke-HorusLxcGuestBaselineCommand $Context $Guest.node $command
  return Get-HorusLxcSshFingerprintFromOutput ([string]$raw)
}

function Invoke-HorusLxcSshKeyRotation([object] $Context, [System.Collections.IDictionary] $Guest) {
  $vmid = [int]$Context.Spec.vmid
  if ($Guest.status -eq 'running') {
    $command = "pct exec $vmid -- sh -ceu 'backup=`$(mktemp -d /root/.horus-ssh-host-keys.XXXXXX); cp -a /etc/ssh/ssh_host_* `"`$backup/`" 2>/dev/null || true; rm -f /etc/ssh/ssh_host_*; if ! ssh-keygen -A || ! sshd -t || ! systemctl restart ssh; then rm -f /etc/ssh/ssh_host_*; cp -a `"`$backup/`"ssh_host_* /etc/ssh/ 2>/dev/null || true; systemctl restart ssh || true; exit 1; fi; rm -rf `"`$backup`"'"
  } else {
    $root = "/var/lib/lxc/$vmid/rootfs"
    $command = "sh -ceu 'pct mount $vmid >/dev/null; trap `"pct unmount $vmid >/dev/null 2>&1 || true`" EXIT; root=$root; backup=`$(mktemp -d `"`$root/root/.horus-ssh-host-keys.XXXXXX`" ); cp -a `"`$root/etc/ssh/`"ssh_host_* `"`$backup/`" 2>/dev/null || true; rm -f `"`$root/etc/ssh/`"ssh_host_*; if ! ssh-keygen -A -f `"`$root`"; then rm -f `"`$root/etc/ssh/`"ssh_host_*; cp -a `"`$backup/`"ssh_host_* `"`$root/etc/ssh/`" 2>/dev/null || true; exit 1; fi; rm -rf `"`$backup`"'"
  }
  $null = Invoke-HorusLxcGuestBaselineCommand $Context $Guest.node $command
}

function Invoke-HorusLxcGuestBaseline([System.Collections.IDictionary] $Spec, [scriptblock] $Remote) {
  Assert-HorusLxcGuestBaselineSpec $Spec
  $context = [pscustomobject]@{ Spec = $Spec; Remote = $Remote }
  $guest = Get-HorusLxcGuestBaselineGuest $context
  $vmid = [int]$Spec.vmid

  $before = Get-HorusLxcSshFingerprint $context $guest
  $needsRotation = $guest.status -eq 'stopped' -or $null -eq $before -or $before -eq $Spec.template_host_key_sha256
  if ($needsRotation) {
    Invoke-HorusLxcSshKeyRotation $context $guest
  }
  $after = Get-HorusLxcSshFingerprint $context $guest
  if ($null -eq $after -or $after -eq $Spec.template_host_key_sha256) {
    throw 'LXC still has a missing or Golden-template ED25519 host key.'
  }
  if ($needsRotation -and $null -ne $before -and $after -eq $before) {
    throw 'LXC ED25519 host key did not change during required rotation.'
  }

  if ($guest.status -eq 'running') {
    $script = Get-HorusLxcGuestBaselineScript
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $command = "pct exec $vmid -- sh -ceu 'echo $encoded | base64 -d | sh; visudo -cf /etc/sudoers >/dev/null; runuser -u jenkins-srv -- sudo -n id -u | grep -qx 0; test `"`$(date +%z)`" = +0300'"
  } else {
    $root = "/var/lib/lxc/$vmid/rootfs"
    $script = Get-HorusLxcGuestBaselineScript $root
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($script))
    $command = "sh -ceu 'pct mount $vmid >/dev/null; trap `"pct unmount $vmid >/dev/null 2>&1 || true`" EXIT; echo $encoded | base64 -d | sh'"
  }

  $null = Invoke-HorusLxcGuestBaselineCommand $context $guest.node $command
  Write-Host "Verified pre-start baseline: $($Spec.hostname) ($vmid), unique SSH identity, Europe/Moscow, Jenkins sudo."
}

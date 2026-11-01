# Pure LXC guest-baseline library. Loading this file performs no operations.
Set-StrictMode -Version Latest

function Assert-HorusLxcGuestBaselineSpec([System.Collections.IDictionary] $Spec) {
  foreach ($key in @('vmid', 'hostname', 'target_node', 'timezone')) {
    if (-not $Spec.Contains($key)) { throw "Missing guest-baseline field: $key" }
  }
  if ([int]$Spec.vmid -lt 100 -or [int]$Spec.vmid -ge 9000) {
    throw 'Only workload LXC VMIDs are supported.'
  }
  if ($Spec.target_node -notmatch '^horus-pmx-node0[1-4]$' -or $Spec.hostname -notmatch '^[a-z0-9-]+$') {
    throw 'Unsafe LXC identity or target node.'
  }
  if ($Spec.timezone -ne 'Europe/Moscow') {
    throw 'The approved HoRus LXC timezone is Europe/Moscow.'
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

function Invoke-HorusLxcGuestBaseline([System.Collections.IDictionary] $Spec, [scriptblock] $Remote) {
  Assert-HorusLxcGuestBaselineSpec $Spec
  $context = [pscustomobject]@{ Spec = $Spec; Remote = $Remote }
  $guest = Get-HorusLxcGuestBaselineGuest $context
  $vmid = [int]$Spec.vmid

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
  Write-Host "Verified guest baseline: $($Spec.hostname) ($vmid), Europe/Moscow, Jenkins sudo."
}

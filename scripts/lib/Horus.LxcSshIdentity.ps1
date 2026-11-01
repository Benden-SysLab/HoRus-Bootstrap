# Pure LXC SSH host-identity library. Loading this file performs no operations.
Set-StrictMode -Version Latest

function Assert-HorusLxcSshIdentitySpec([System.Collections.IDictionary] $Spec) {
  foreach ($key in @('vmid', 'hostname', 'template_vmid', 'target_node', 'template_host_key_sha256')) {
    if (-not $Spec.Contains($key)) { throw "Missing SSH identity field: $key" }
  }
  if ([int]$Spec.vmid -lt 100 -or [int]$Spec.vmid -ge 9000 -or [int]$Spec.template_vmid -ne 9001) {
    throw 'Only workload clones of external Golden LXC 9001 are supported.'
  }
  if ($Spec.target_node -notmatch '^horus-pmx-node0[1-4]$' -or $Spec.hostname -notmatch '^[a-z0-9-]+$') {
    throw 'Unsafe LXC identity or target node.'
  }
  if ($Spec.template_host_key_sha256 -notmatch '^SHA256:[A-Za-z0-9+/=]+$') {
    throw 'Golden LXC ED25519 fingerprint must use OpenSSH SHA256 format.'
  }
}

function Invoke-HorusLxcSshIdentityCommand([object] $Context, [string] $Node, [string] $Command) {
  if ($Node -notmatch '^horus-pmx-node0[1-4]$') { throw "Unapproved node: $Node" }
  return (& $Context.Remote $Node $Command)
}

function Get-HorusLxcSshIdentityGuest([object] $Context) {
  $raw = Invoke-HorusLxcSshIdentityCommand $Context $Context.Spec.target_node 'pvesh get /cluster/resources --type vm --output-format json'
  $guests = @($raw | ConvertFrom-Json -AsHashtable | Where-Object { [int]$_.vmid -eq [int]$Context.Spec.vmid })
  if ($guests.Count -ne 1) { throw 'Expected exactly one LXC with the requested VMID.' }
  $guest = $guests[0]
  if ($guest.type -ne 'lxc' -or $guest.name -ne $Context.Spec.hostname -or ($guest.Contains('template') -and $guest.template)) {
    throw "VMID $($Context.Spec.vmid) identity mismatch; refusing SSH key changes."
  }
  if ($guest.node -ne $Context.Spec.target_node) { throw 'LXC is not on its Terraform target node.' }
  if ($guest.status -notin @('running', 'stopped')) { throw "Unsupported LXC status: $($guest.status)" }
  return $guest
}

function Get-HorusSshFingerprintFromOutput([string] $Output) {
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
  $raw = Invoke-HorusLxcSshIdentityCommand $Context $Guest.node $command
  return Get-HorusSshFingerprintFromOutput ([string]$raw)
}

function Invoke-HorusLxcSshKeyRotation([object] $Context, [System.Collections.IDictionary] $Guest) {
  $vmid = [int]$Context.Spec.vmid
  if ($Guest.status -eq 'running') {
    $command = "pct exec $vmid -- sh -ceu 'backup=`$(mktemp -d /root/.horus-ssh-host-keys.XXXXXX); cp -a /etc/ssh/ssh_host_* `"`$backup/`" 2>/dev/null || true; rm -f /etc/ssh/ssh_host_*; if ! ssh-keygen -A || ! sshd -t || ! systemctl restart ssh; then rm -f /etc/ssh/ssh_host_*; cp -a `"`$backup/`"ssh_host_* /etc/ssh/ 2>/dev/null || true; systemctl restart ssh || true; exit 1; fi; rm -rf `"`$backup`"'"
  } else {
    $root = "/var/lib/lxc/$vmid/rootfs"
    $command = "sh -ceu 'pct mount $vmid >/dev/null; trap `"pct unmount $vmid >/dev/null 2>&1 || true`" EXIT; root=$root; backup=`$(mktemp -d `"`$root/root/.horus-ssh-host-keys.XXXXXX`" ); cp -a `"`$root/etc/ssh/`"ssh_host_* `"`$backup/`" 2>/dev/null || true; rm -f `"`$root/etc/ssh/`"ssh_host_*; if ! ssh-keygen -A -f `"`$root`"; then rm -f `"`$root/etc/ssh/`"ssh_host_*; cp -a `"`$backup/`"ssh_host_* `"`$root/etc/ssh/`" 2>/dev/null || true; exit 1; fi; rm -rf `"`$backup`"'"
  }
  $null = Invoke-HorusLxcSshIdentityCommand $Context $Guest.node $command
}

function Invoke-HorusLxcSshIdentity([System.Collections.IDictionary] $Spec, [scriptblock] $Remote) {
  Assert-HorusLxcSshIdentitySpec $Spec
  $context = [pscustomobject]@{ Spec = $Spec; Remote = $Remote }
  $guest = Get-HorusLxcSshIdentityGuest $context
  $before = Get-HorusLxcSshFingerprint $context $guest

  # A stopped provider clone has never passed the identity barrier. For a
  # running legacy LXC, mutate only a missing key or the exact inherited key.
  $needsRotation = $guest.status -eq 'stopped' -or $null -eq $before -or $before -eq $Spec.template_host_key_sha256
  if ($needsRotation) {
    Invoke-HorusLxcSshKeyRotation $context $guest
  }

  $after = Get-HorusLxcSshFingerprint $context $guest
  if ($null -eq $after -or $after -eq $Spec.template_host_key_sha256) {
    throw 'LXC still has a missing or Golden-template ED25519 host key after identity reconciliation.'
  }
  if ($needsRotation -and $null -ne $before -and $after -eq $before) {
    throw 'LXC ED25519 host key did not change during required rotation.'
  }

  $action = if ($needsRotation) { 'rotated' } else { 'already unique' }
  Write-Host "Verified SSH identity: $($Spec.hostname) ($($Spec.vmid)), $action, $after."
}

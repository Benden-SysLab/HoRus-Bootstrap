# Pure LXC placement library. Loading this file performs no remote operations.
Set-StrictMode -Version Latest

function Assert-HorusPlacementSpec([System.Collections.IDictionary] $Spec) {
  foreach ($key in @('vmid', 'hostname', 'template_vmid', 'target_node', 'root_storage', 'disk_size', 'bridge', 'vlan_id', 'ip_address', 'gateway', 'private_mounts', 'features', 'allow_shutdown', 'start_on_boot')) {
    if (-not $Spec.Contains($key)) { throw "Missing placement field: $key" }
  }
  if ([int]$Spec.vmid -lt 100 -or [int]$Spec.vmid -ge 9000 -or [int]$Spec.template_vmid -ne 9001) { throw 'Only workload clones of external Golden LXC 9001 are supported.' }
  if ($Spec.target_node -notmatch '^horus-pmx-node0[1-4]$' -or $Spec.hostname -notmatch '^[a-z0-9-]+$') { throw 'Unsafe identity or target node.' }
  if ($Spec.root_storage -ne 'local-lvm' -or [decimal]$Spec.disk_size -lt 8) { throw 'Final rootfs must be local-lvm and at least the 8 GiB Golden baseline.' }
  if ($Spec.bridge -notmatch '^[A-Za-z0-9_.-]+$' -or $Spec.ip_address -notmatch '^\d{1,3}(\.\d{1,3}){3}/\d{1,2}$' -or $Spec.gateway -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or [int]$Spec.vlan_id -lt 1 -or [int]$Spec.vlan_id -gt 4094) { throw 'Unsafe network configuration.' }
  foreach ($mount in @($Spec.private_mounts)) {
    if ($mount.datastore_id -notmatch '^[A-Za-z0-9_.-]+$' -or $mount.path -notmatch '^/[A-Za-z0-9_./-]+$' -or $mount.size -ne '0') {
      throw 'Unsafe private storage manifest.'
    }
  }
}

function Invoke-HorusPlacementCommand([object] $Context, [string] $Node, [string] $Command) {
  if ($Node -notmatch '^horus-pmx-node0[1-4]$') { throw "Unapproved node: $Node" }
  return (& $Context.Remote $Node $Command)
}

function Get-HorusPlacementGuest([object] $Context) {
  $raw = Invoke-HorusPlacementCommand $Context $Context.Spec.target_node 'pvesh get /cluster/resources --type vm --output-format json'
  $guests = @($raw | ConvertFrom-Json -AsHashtable | Where-Object { [int]$_.vmid -eq [int]$Context.Spec.vmid })
  if ($guests.Count -gt 1) { throw 'Ambiguous VMID in cluster inventory.' }
  if (-not $guests.Count) { return $null }
  $guest = $guests[0]
  if ($guest.type -ne 'lxc' -or $guest.name -ne $Context.Spec.hostname -or ($guest.Contains('template') -and $guest.template)) {
    throw "VMID $($Context.Spec.vmid) identity mismatch; refusing all changes."
  }
  if ($guest.node -notmatch '^horus-pmx-node0[1-4]$') { throw 'Guest is on an unapproved node.' }
  return $guest
}

function Get-HorusPlacementConfig([object] $Context, [string] $Node) {
  $raw = Invoke-HorusPlacementCommand $Context $Node "pvesh get /nodes/$Node/lxc/$($Context.Spec.vmid)/config --output-format json"
  return ($raw | ConvertFrom-Json -AsHashtable)
}

function Get-HorusPlacementOptions([string] $Value) {
  $result = @{}
  foreach ($part in $Value.Split(',')) {
    $pair = $part.Split('=', 2)
    if ($pair.Count -eq 2) { $result[$pair[0]] = $pair[1] } else { $result.volume = $part }
  }
  return $result
}

function Get-HorusPlacementRootSize([System.Collections.IDictionary] $Config) {
  if (-not $Config.Contains('rootfs')) { throw 'CT has no rootfs.' }
  $root = Get-HorusPlacementOptions $Config.rootfs
  if (-not $root.ContainsKey('size') -or $root.size -notmatch '^(\d+(?:\.\d+)?)([KMGT])$') { throw 'Cannot read actual rootfs size.' }
  $size = [decimal]$Matches[1]
  switch ($Matches[2]) {
    'K' { $size /= 1048576 }
    'M' { $size /= 1024 }
    'T' { $size *= 1024 }
  }
  return $size
}

function Test-HorusPlacementFeatures([System.Collections.IDictionary] $Config, [System.Collections.IDictionary] $Spec) {
  $actual = @{}
  if ($Config.Contains('features') -and $Config.features) {
    foreach ($part in $Config.features.Split(',')) {
      $pair = $part.Split('=', 2)
      if ($pair.Count -eq 2) { $actual[$pair[0]] = $pair[1] }
    }
  }
  foreach ($name in @('nesting', 'keyctl', 'fuse', 'mknod')) {
    $expected = if ($Spec.features[$name]) { '1' } else { '0' }
    $observed = if ($actual.ContainsKey($name)) { $actual[$name] } else { '0' }
    if ($observed -ne $expected) { return $false }
  }
  return $true
}

function Assert-HorusPlacementConfig([object] $Context, [System.Collections.IDictionary] $Config) {
  $spec = $Context.Spec
  if ($Config.Contains('lock') -and $Config.lock) { throw "CT $($spec.vmid) is locked ($($Config.lock)); never automatically unlock." }
  if ($Config.hostname -ne $spec.hostname -or ($Config.Contains('template') -and $Config.template)) { throw 'CT config identity/template mismatch.' }
  if (-not $Config.Contains('unprivileged') -or [int]$Config.unprivileged -ne 1) { throw 'Expected an unprivileged LXC.' }
  if (-not $Config.Contains('onboot') -or [int]$Config.onboot -ne 1 -or -not $spec.start_on_boot) { throw 'Expected start_on_boot=true before final start.' }

  $root = Get-HorusPlacementOptions $Config.rootfs
  if ($root.volume -notmatch '^(local-lvm|storage-infra):[^,\s]+$') { throw 'Unexpected rootfs storage; refusing storage remapping.' }
  $null = Get-HorusPlacementRootSize $Config

  if (-not $Config.Contains('net0')) { throw 'CT has no net0; refusing start.' }
  $net = Get-HorusPlacementOptions $Config.net0
  $tag = if ($net.ContainsKey('tag')) { [int]$net.tag } else { 0 }
  if ($net.name -ne 'eth0' -or $net.bridge -ne $spec.bridge -or $net.ip -ne $spec.ip_address -or $net.gw -ne $spec.gateway -or $tag -ne [int]$spec.vlan_id) {
    throw 'Network/IP/VLAN differs from the Terraform manifest; refusing start.'
  }
  if (-not (Test-HorusPlacementFeatures $Config $spec)) { throw 'Provider-owned LXC features differ from the Terraform manifest.' }

  $actualMounts = @($Config.Keys | Where-Object { $_ -match '^mp\d+$' } | Sort-Object { [int]$_.Substring(2) })
  if ($actualMounts.Count -ne @($spec.private_mounts).Count) { throw 'Private mount count differs from the Terraform manifest.' }
  for ($i = 0; $i -lt @($spec.private_mounts).Count; $i++) {
    $options = Get-HorusPlacementOptions $Config["mp$i"]
    $expected = $spec.private_mounts[$i]
    if ($options.mp -ne $expected.path -or $options.volume -notmatch ('^' + [regex]::Escape($expected.datastore_id) + ':')) {
      throw "Private mount mp$i differs from the Terraform-managed storage volume."
    }
  }
}

function Wait-HorusPlacementState([object] $Context, [scriptblock] $Sleep, [string] $Node, [string] $Status) {
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    $guest = Get-HorusPlacementGuest $Context
    if ($null -ne $guest -and $guest.node -eq $Node -and $guest.status -eq $Status) { return $guest }
    & $Sleep 1
  }
  throw "CT did not reach $Node/$Status; refusing to continue."
}

function Invoke-HorusLxcPlacement([System.Collections.IDictionary] $Spec, [scriptblock] $Remote, [scriptblock] $Sleep = { param($Seconds) Start-Sleep -Seconds $Seconds }) {
  Assert-HorusPlacementSpec $Spec
  $context = [pscustomobject]@{ Spec = $Spec; Remote = $Remote }
  $guest = Get-HorusPlacementGuest $context
  if ($null -eq $guest) { throw "Expected LXC VMID $($Spec.vmid) does not exist after provider clone." }
  if ($guest.node -ne $Spec.target_node) { throw "CT is on $($guest.node), expected $($Spec.target_node); node migration is outside this helper." }

  $config = Get-HorusPlacementConfig $context $guest.node
  Assert-HorusPlacementConfig $context $config
  $root = Get-HorusPlacementOptions $config.rootfs
  $needsMove = $root.volume -notmatch '^local-lvm:'

  if ($guest.status -eq 'running' -and $needsMove) {
    if (-not $Spec.allow_shutdown) { throw 'Running CT needs placement/rootfs correction; set allow_lxc_shutdown=true only for an approved maintenance window.' }
    $null = Invoke-HorusPlacementCommand $context $guest.node "pct shutdown $($Spec.vmid) --timeout 120 --forceStop 0"
    $guest = Wait-HorusPlacementState $context $Sleep $guest.node 'stopped'
  }

  $root = Get-HorusPlacementOptions $config.rootfs
  if ($root.volume -match '^storage-infra:') {
    # Keep the source as an unused recovery volume. No automatic data deletion.
    $null = Invoke-HorusPlacementCommand $context $guest.node "pct move-volume $($Spec.vmid) rootfs local-lvm"
    $config = Get-HorusPlacementConfig $context $guest.node
  } elseif ($root.volume -notmatch '^local-lvm:') {
    throw 'Rootfs is on an unexpected datastore; refusing move/start.'
  }

  $actualSize = Get-HorusPlacementRootSize $config
  if ($actualSize -lt [decimal]$Spec.disk_size) {
    $null = Invoke-HorusPlacementCommand $context $guest.node "pct resize $($Spec.vmid) rootfs $($Spec.disk_size)G"
    $config = Get-HorusPlacementConfig $context $guest.node
    $actualSize = Get-HorusPlacementRootSize $config
    if ($actualSize -lt [decimal]$Spec.disk_size) { throw 'Rootfs resize did not reach the requested size; refusing start.' }
  } elseif ($actualSize -gt [decimal]$Spec.disk_size) {
    Write-Warning "Rootfs is $actualSize GiB, desired $($Spec.disk_size) GiB; shrinking is forbidden."
  }

  Assert-HorusPlacementConfig $context $config
  $root = Get-HorusPlacementOptions $config.rootfs
  if ($guest.node -ne $Spec.target_node -or $root.volume -notmatch '^local-lvm:' -or (Get-HorusPlacementRootSize $config) -lt [decimal]$Spec.disk_size) {
    throw 'Final node/rootfs/size verification failed; CT was not started.'
  }

  if ($guest.status -eq 'stopped') {
    $null = Invoke-HorusPlacementCommand $context $guest.node "pct start $($Spec.vmid)"
    $guest = Wait-HorusPlacementState $context $Sleep $Spec.target_node 'running'
  }
  if ($guest.node -ne $Spec.target_node -or $guest.status -ne 'running') { throw 'Final running-node verification failed.' }
  Write-Host "Verified: $($Spec.hostname) ($($Spec.vmid)), $($guest.node), local-lvm, running."
}

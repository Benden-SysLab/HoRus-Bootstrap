#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/lib/Horus.LxcPlacement.ps1')

function Assert-Test([bool] $Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
}

function New-Fixture {
  $spec = @{
    vmid = 405; hostname = 'horus-s3-srv01'; template_vmid = 9001
    target_node = 'horus-pmx-node04'; root_storage = 'local-lvm'; disk_size = 16
    bridge = 'vmbr0'; vlan_id = 150; ip_address = '198.51.100.88/24'; gateway = '198.51.100.81'
    private_mounts = @(@{ datastore_id = 'logs-data'; path = '/srv/example/logs'; size = '0' })
    features = @{ nesting = $true; keyctl = $true; fuse = $true; mknod = $false; mount = @('nfs', 'cifs') }
    allow_shutdown = $false; start_on_boot = $true
  }
  $state = @{
    Node = 'horus-pmx-node04'; Status = 'stopped'; Name = $spec.hostname
    Config = @{
      hostname = $spec.hostname; unprivileged = 1; onboot = 1
      rootfs = 'storage-infra:vm-405-disk-0,size=8G'
      net0 = 'name=eth0,bridge=vmbr0,ip=198.51.100.88/24,gw=198.51.100.81,tag=150'
      features = 'nesting=1,keyctl=1,fuse=1,mknod=0,mount=nfs;cifs'
      mp0 = 'logs-data:vm-405-disk-0,mp=/srv/example/logs,size=0'
    }
    Commands = [System.Collections.Generic.List[string]]::new()
  }
  $remote = {
    param($node, $command)
    $state.Commands.Add("$node $command")
    if ($command -eq 'pvesh get /cluster/resources --type vm --output-format json') {
      return (ConvertTo-Json -Compress -InputObject @(@{ vmid = 405; node = $state.Node; status = $state.Status; type = 'lxc'; name = $state.Name; template = 0 }))
    }
    if ($command -match '^pvesh get /nodes/.+/lxc/405/config') { return ($state.Config | ConvertTo-Json -Compress) }
    if ($command -eq 'pct move-volume 405 rootfs local-lvm') { $state.Config.rootfs = $state.Config.rootfs -replace '^storage-infra:', 'local-lvm:'; return '' }
    if ($command -eq 'pct resize 405 rootfs 16G') { $state.Config.rootfs = $state.Config.rootfs -replace 'size=8G', 'size=16G'; return '' }
    if ($command -eq 'pct shutdown 405 --timeout 120 --forceStop 0') { $state.Status = 'stopped'; return '' }
    if ($command -eq 'pct start 405') { $state.Status = 'running'; return '' }
    throw "Unexpected command: $command"
  }.GetNewClosure()
  return @{ Spec = $spec; State = $state; Remote = $remote; Sleep = { param($seconds) } }
}

function Assert-Fails([scriptblock] $Body) {
  $failed = $false
  try { & $Body } catch { $failed = $true }
  Assert-Test $failed 'Expected a fail-closed error.'
}

$passed = 0

$f = New-Fixture
Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep
$commands = $f.State.Commands -join "`n"
Assert-Test ($commands.IndexOf('pct move-volume') -lt $commands.IndexOf('pct start')) 'CT started before the local rootfs move.'
Assert-Test ($commands.IndexOf('pct move-volume') -lt $commands.IndexOf('pct resize') -and $commands.IndexOf('pct resize') -lt $commands.IndexOf('pct start')) 'Move/resize/start order is wrong.'
Assert-Test ($f.State.Status -eq 'running' -and $f.State.Config.rootfs -match '^local-lvm:.*size=16G') 'Final state is wrong.'
$passed++

$f = New-Fixture
$f.State.Node = 'horus-pmx-node03'
Assert-Fails { Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep }
Assert-Test (-not ($f.State.Commands -match 'pct migrate')) 'Helper attempted obsolete node migration.'
$passed++

$f = New-Fixture
$f.State.Config.rootfs = 'unexpected:vm-405-disk-0,size=8G'
Assert-Fails { Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep }
Assert-Test (-not ($f.State.Commands -match 'pct (move-volume|resize|start)')) 'Unexpected storage was mutated.'
$passed++

$f = New-Fixture
$f.State.Config.rootfs = 'local-lvm:vm-405-disk-0,size=40G'
Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep
Assert-Test (-not ($f.State.Commands -match 'pct resize')) 'A rootfs shrink was attempted.'
$passed++

$f = New-Fixture
$f.State.Config.rootfs = 'local-lvm:vm-405-disk-0,size=8G'
Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep
Assert-Test (($f.State.Commands -match 'pct resize').Count -eq 1 -and $f.State.Status -eq 'running') 'Safe upward resize/start did not complete.'
$passed++

$f = New-Fixture
$f.State.Status = 'running'
$f.State.Config.rootfs = 'local-lvm:vm-405-disk-0,size=16G'
Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep
Assert-Test (-not ($f.State.Commands -match 'pct (move-volume|resize|shutdown|start)')) 'Already-correct running CT was mutated.'
$passed++

$f = New-Fixture
$f.State.Config.onboot = 0
Assert-Fails { Invoke-HorusLxcPlacement $f.Spec $f.Remote $f.Sleep }
Assert-Test (-not ($f.State.Commands -match 'pct (move-volume|resize|start)')) 'CT without onboot was mutated or started.'
$passed++

Write-Host "PASS: $passed offline LXC placement tests."

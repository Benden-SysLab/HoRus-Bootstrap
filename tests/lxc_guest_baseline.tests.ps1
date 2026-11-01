#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/lib/Horus.LxcGuestBaseline.ps1')

function Assert-Test([bool] $Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
}

function Assert-Fails([scriptblock] $Body) {
  $failed = $false
  try { & $Body } catch { $failed = $true }
  Assert-Test $failed 'Expected a fail-closed error.'
}

function New-Fixture([string] $Status = 'stopped') {
  $spec = @{
    vmid = 401; hostname = 'horus-grf-srv01'; target_node = 'horus-pmx-node04'
    timezone = 'Europe/Moscow'
  }
  $state = @{
    Node = 'horus-pmx-node04'; Status = $Status; Name = $spec.hostname
    Commands = [System.Collections.Generic.List[string]]::new()
  }
  $remote = {
    param($node, $command)
    $state.Commands.Add("$node $command")
    if ($command -eq 'pvesh get /cluster/resources --type vm --output-format json') {
      return (ConvertTo-Json -Compress -InputObject @(@{
            vmid = 401; node = $state.Node; status = $state.Status
            type = 'lxc'; name = $state.Name; template = 0
          }))
    }
    if ($command -match 'base64 -d') { return '' }
    throw "Unexpected command: $command"
  }.GetNewClosure()
  return @{ Spec = $spec; State = $state; Remote = $remote }
}

$passed = 0

$f = New-Fixture -Status stopped
Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote
$commands = $f.State.Commands -join "`n"
Assert-Test ($commands -match 'pct mount 401' -and $commands -match 'base64 -d') 'Stopped clone was not configured offline.'
$passed++

$f = New-Fixture -Status running
Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote
$commands = $f.State.Commands -join "`n"
Assert-Test ($commands -match 'pct exec 401' -and $commands -match 'date \+%z') 'Running reconciliation did not verify the timezone.'
$passed++

$script = Get-HorusLxcGuestBaselineScript '/var/lib/lxc/401/rootfs'
Assert-Test ($script -match 'Europe/Moscow' -and $script -match 'NOPASSWD: ALL') 'Baseline script omitted timezone or Jenkins sudo.'
Assert-Test ($script -match 'chown --reference=') 'Offline baseline did not preserve unprivileged UID/GID mapping.'
$passed++

$f = New-Fixture
$f.State.Node = 'horus-pmx-node03'
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test (-not (($f.State.Commands -join "`n") -match 'base64 -d')) 'Wrong-node LXC was mutated.'
$passed++

$f = New-Fixture
$f.State.Name = 'unexpected-host'
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test (-not (($f.State.Commands -join "`n") -match 'base64 -d')) 'Identity-mismatched LXC was mutated.'
$passed++

$f = New-Fixture
$f.Spec.vmid = 9001
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test ($f.State.Commands.Count -eq 0) 'Golden template VMID was queried or mutated.'
$passed++

$f = New-Fixture
$f.Spec.timezone = 'Etc/UTC'
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test ($f.State.Commands.Count -eq 0) 'Unapproved timezone reached remote execution.'
$passed++

Write-Host "PASS: $passed offline LXC guest-baseline tests."

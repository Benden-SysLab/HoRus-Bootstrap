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

function New-Fixture([string] $Status = 'stopped', [string] $Fingerprint = 'SHA256:GoldenTemplateFingerprint000000000000000') {
  $spec = @{
    vmid = 401; hostname = 'horus-grf-srv01'; template_vmid = 9001
    target_node = 'horus-pmx-node04'; timezone = 'Europe/Moscow'
    template_host_key_sha256 = 'SHA256:GoldenTemplateFingerprint000000000000000'
  }
  $state = @{
    Node = 'horus-pmx-node04'; Status = $Status; Name = $spec.hostname
    Fingerprint = $Fingerprint; Commands = [System.Collections.Generic.List[string]]::new()
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
    if ($command -match 'ssh-keygen -lf .+ssh_host_ed25519_key\.pub') {
      if ($null -eq $state.Fingerprint) { return 'MISSING' }
      return "256 $($state.Fingerprint) root@test (ED25519)"
    }
    if ($command -match 'ssh-keygen -A') {
      $state.Fingerprint = 'SHA256:UniqueWorkloadFingerprint111111111111111'
      return ''
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
Assert-Test ($commands -match 'ssh-keygen -A -f' -and $commands -match 'base64 -d') 'Stopped clone did not receive identity and baseline.'
Assert-Test ((Get-HorusLxcGuestBaselineScript '/var/lib/lxc/401/rootfs') -match 'chown --reference=') 'Stopped clone host keys did not inherit mapped root ownership.'
$passed++

$f = New-Fixture -Status running -Fingerprint 'SHA256:AlreadyUniqueFingerprint222222222222222222'
Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote
$commands = $f.State.Commands -join "`n"
Assert-Test ($commands -notmatch 'ssh-keygen -A' -and $commands -match 'date \+%z') 'Running reconciliation changed a unique key or skipped runtime validation.'
$passed++

$f = New-Fixture
$f.State.Name = 'unexpected-host'
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test (-not (($f.State.Commands -join "`n") -match 'ssh-keygen -A|base64 -d')) 'Identity-mismatched LXC was mutated.'
$passed++

$f = New-Fixture
$f.Spec.vmid = 9001
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test ($f.State.Commands.Count -eq 0) 'Golden template was queried or mutated.'
$passed++

$f = New-Fixture
$f.Spec.timezone = 'Etc/UTC'
Assert-Fails { Invoke-HorusLxcGuestBaseline $f.Spec $f.Remote }
Assert-Test ($f.State.Commands.Count -eq 0) 'Unapproved timezone reached remote execution.'
$passed++

Write-Host "PASS: $passed offline LXC pre-start baseline tests."

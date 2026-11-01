#requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../scripts/lib/Horus.LxcSshIdentity.ps1')

function Assert-Test([bool] $Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
}

function Assert-Fails([scriptblock] $Body) {
  $failed = $false
  try { & $Body } catch { $failed = $true }
  Assert-Test $failed 'Expected a fail-closed error.'
}

function New-Fixture([string] $Status = 'running', [string] $Fingerprint = 'SHA256:GoldenTemplateFingerprint000000000000000') {
  $spec = @{
    vmid = 401; hostname = 'horus-grf-srv01'; template_vmid = 9001
    target_node = 'horus-pmx-node04'
    template_host_key_sha256 = 'SHA256:GoldenTemplateFingerprint000000000000000'
  }
  $state = @{
    Node = 'horus-pmx-node04'; Status = $Status; Name = $spec.hostname
    Fingerprint = $Fingerprint
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
    if ($command -match 'ssh-keygen -lf .+ssh_host_ed25519_key\.pub') {
      if ($command -match 'rm -f .+ssh_host_' -or $command -match 'ssh-keygen -A') {
        throw 'Fingerprint read unexpectedly included a mutation.'
      }
      if ($null -eq $state.Fingerprint) { return 'MISSING' }
      return "256 $($state.Fingerprint) root@test (ED25519)"
    }
    if ($command -match 'ssh-keygen -A') {
      $state.Fingerprint = 'SHA256:UniqueWorkloadFingerprint111111111111111'
      return ''
    }
    throw "Unexpected command: $command"
  }.GetNewClosure()
  return @{ Spec = $spec; State = $state; Remote = $remote }
}

$passed = 0

$f = New-Fixture -Status running
Invoke-HorusLxcSshIdentity $f.Spec $f.Remote
Assert-Test (($f.State.Commands -match 'ssh-keygen -A').Count -eq 1) 'Running clone with inherited key was not rotated exactly once.'
Assert-Test ($f.State.Fingerprint -ne $f.Spec.template_host_key_sha256) 'Running clone retained the Golden key.'
$passed++

$f = New-Fixture -Status running -Fingerprint 'SHA256:AlreadyUniqueFingerprint222222222222222222'
Invoke-HorusLxcSshIdentity $f.Spec $f.Remote
Assert-Test (($f.State.Commands -match 'ssh-keygen -A').Count -eq 0) 'An already-unique running LXC was mutated.'
$passed++

$f = New-Fixture -Status stopped -Fingerprint 'SHA256:AlreadyUniqueButUnstarted333333333333333'
Invoke-HorusLxcSshIdentity $f.Spec $f.Remote
Assert-Test (($f.State.Commands -match 'ssh-keygen -A -f').Count -eq 1) 'A stopped provider clone did not receive a fresh offline identity.'
$passed++

$f = New-Fixture
$f.State.Node = 'horus-pmx-node03'
Assert-Fails { Invoke-HorusLxcSshIdentity $f.Spec $f.Remote }
Assert-Test (($f.State.Commands -match 'ssh-keygen -A').Count -eq 0) 'Wrong-node LXC was mutated.'
$passed++

$f = New-Fixture
$f.State.Name = 'unexpected-host'
Assert-Fails { Invoke-HorusLxcSshIdentity $f.Spec $f.Remote }
Assert-Test (($f.State.Commands -match 'ssh-keygen -A').Count -eq 0) 'Identity-mismatched LXC was mutated.'
$passed++

$f = New-Fixture
$f.Remote = {
  param($node, $command)
  $f.State.Commands.Add("$node $command")
  if ($command -eq 'pvesh get /cluster/resources --type vm --output-format json') {
    return (ConvertTo-Json -Compress -InputObject @(@{ vmid = 401; node = $f.State.Node; status = 'running'; type = 'lxc'; name = $f.State.Name; template = 0 }))
  }
  if ($command -match 'ssh-keygen -lf') { return "256 $($f.Spec.template_host_key_sha256) root@test (ED25519)" }
  if ($command -match 'ssh-keygen -A') { return '' }
  throw "Unexpected command: $command"
}.GetNewClosure()
Assert-Fails { Invoke-HorusLxcSshIdentity $f.Spec $f.Remote }
$passed++

$f = New-Fixture
$f.Spec.vmid = 9001
Assert-Fails { Invoke-HorusLxcSshIdentity $f.Spec $f.Remote }
Assert-Test ($f.State.Commands.Count -eq 0) 'Golden template VMID was queried or mutated.'
$passed++

Write-Host "PASS: $passed offline LXC SSH identity tests."

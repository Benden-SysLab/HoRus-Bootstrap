#requires -Version 7.0
# Internal Terraform entry point. Topology is supplied only by Terraform JSON.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/Horus.LxcPlacement.ps1')

if (-not $env:HORUS_SPEC_JSON) { throw 'HORUS_SPEC_JSON is required.' }
$spec = $env:HORUS_SPEC_JSON | ConvertFrom-Json -AsHashtable
Assert-HorusPlacementSpec $spec

$ssh = (Get-Command ssh.exe -CommandType Application -ErrorAction Stop).Source
$keyPath = $env:HORUS_SSH_KEY_PATH
if ($keyPath) { $keyPath = (Resolve-Path -LiteralPath $keyPath -ErrorAction Stop).Path }

$remote = {
  param([string] $Node, [string] $Command)
  $arguments = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=yes', '-l', 'root')
  if ($keyPath) { $arguments += @('-i', $keyPath) }
  $result = & $ssh @arguments $Node $Command 2>&1
  if ($LASTEXITCODE -ne 0) { throw "SSH operation failed on $Node (exit $LASTEXITCODE): $Command`n$($result -join "`n")" }
  return ($result -join "`n")
}.GetNewClosure()

Invoke-HorusLxcPlacement $spec $remote

#!/usr/bin/env pwsh

if($null -eq $env:ATOM_PATH){
	Set-StrictMode -Version Latest
	$ErrorActionPreference = "Stop"
	Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
	$VerbosePreference = "Continue"
}

"Working directory: {0}[4m{1}{0}[24m" -f [char]0x1B, (Get-Location) | Write-Host
assertValidProject
setupEnvironment

# Download Atom
if($env:ATOM_RELEASE){
	startFold "install-atom" "Installing Atom ($env:ATOM_RELEASE)"
	downloadAtom -release $env:ATOM_RELEASE $env:ATOM_ASSET_NAME -reuseExisting
}
else{
	$channel = $env:ATOM_CHANNEL.tolower()
	startFold "install-atom" "Installing Atom (Latest $channel release)"
	downloadAtom -channel $channel $env:ATOM_ASSET_NAME -reuseExisting
}

# Extract files
unzip $env:ATOM_ASSET_NAME $env:ATOM_PATH -noOverwrite

# Dump environment variables
if($env:TRAVIS_JOB_ID -or $env:GITHUB_ACTIONS -or $env:APPVEYOR -or $env:ATOM_CI_DUMP_ENV){
	startFold 'env-dump' 'Dumping environment variables'
	dumpEnv
	endFold 'env-dump'
}

endFold 'install-atom'

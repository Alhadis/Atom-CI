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
	downloadAtom -reuseExisting -release $env:ATOM_RELEASE $env:ATOM_ASSET_NAME -saveAs "atom.zip"
}
else{
	$channel = $env:ATOM_CHANNEL.tolower()
	startFold "install-atom" "Installing Atom (Latest $channel release)"
	downloadAtom -reuseExisting -channel $channel $env:ATOM_ASSET_NAME -saveAs "atom.zip"
}

# Extract files
unzip "atom.zip" $env:ATOM_PATH

# Create wrapper for Atom binary
$wrapper = Join-Path (Split-Path $env:NPM_SCRIPT_PATH) "atom"
makeWrapper $env:ATOM_SCRIPT_PATH $wrapper

# Dump environment variables
if($env:TRAVIS_JOB_ID -or $env:GITHUB_ACTIONS -or $env:ATOM_CI_DUMP_ENV){
	startFold 'env-dump' 'Dumping environment variables'
	$env = [Environment]::GetEnvironmentVariables()
	$env.keys | Sort-Object | % {
		[PSCustomObject] @{ Name = $_; Value = $env[$_] }
	} | Format-Table -Wrap
	endFold 'env-dump'
}

endFold 'install-atom'

#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
$VerbosePreference = "Continue"

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

# Dump environment variables
if($env:TRAVIS_JOB_ID -or $env:GITHUB_ACTIONS -or $env:ATOM_CI_DUMP_ENV){
	startFold 'env-dump' 'Dumping environment variables'
	$env = [Environment]::GetEnvironmentVariables()
	$env.keys | Sort-Object | ForEach-Object {
		[PSCustomObject] @{ Name = $_; Value = $env[$_] }
	} | Format-Table -Wrap
	endFold 'env-dump'
}

endFold 'install-atom'

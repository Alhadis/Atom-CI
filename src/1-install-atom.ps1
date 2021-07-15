#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
$VerbosePreference = "Continue"

assertValidProject
setEnv "ELECTRON_NO_ATTACH_CONSOLE" "true"
setEnv "ELECTRON_ENABLE_LOGGING" "YES"


# Resolve what version of Atom we're downloading
if($env:ATOM_RELEASE){
	title "Installing Atom ($env:ATOM_RELEASE)"
	$channel = "stable"
	if($env:ATOM_RELEASE -match "-beta"){
		$channel = "beta"
	}
	setEnv "ATOM_CHANNEL" $channel
	downloadAtom -reuseExisting -release $env:ATOM_RELEASE -saveAs "atom.zip"
}
else{
	if(-not $env:ATOM_CHANNEL){
		setEnv "ATOM_CHANNEL" "stable"
	}
	elseif(-not $env:ATOM_CHANNEL -in "beta", "stable"){
		die "Unsupported channel: $env:ATOM_CHANNEL"
	}
	$channel = $env:ATOM_CHANNEL.tolower()
	startFold "install-atom" "Installing Atom (Latest $channel release)"
	downloadAtom -reuseExisting -channel $channel -saveAs "atom.zip"
}

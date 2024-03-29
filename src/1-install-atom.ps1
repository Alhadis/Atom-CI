#!/usr/bin/env pwsh

if($null -eq $env:ATOM_PATH){
	Set-StrictMode -Version Latest
	$ErrorActionPreference = "Stop"
	Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
	$VerbosePreference = "Continue"
}

switchToProject
setupEnvironment

# Initialise display server on Linux
$pidFile = "/tmp/custom_xvfb_99.pid"
if($IsLinux -and -not (exists $pidFile)){
	$daemon = which "start-stop-daemon"
	$xvfb   = which "Xvfb"
	if($daemon -and $xvfb){
		cmd "$daemon" "-Sqombp" $pidFile "-x" "$xvfb" "--" ":99" "-ac" "-screen" 0 1280x1024x16
		setEnv DISPLAY ":99"
	}
}

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
if($env:ATOM_ASSET_NAME.endsWith(".deb")){
	cmd dpkg-deb "-x" $env:ATOM_ASSET_NAME $env:ATOM_PATH
}
else{
	unzip $env:ATOM_ASSET_NAME $env:ATOM_PATH -noOverwrite
}

# Dump environment variables
if((isCI) -or $env:ATOM_CI_DUMP_ENV){
	startFold 'env-dump' 'Dumping environment variables'
	dumpEnv
	endFold 'env-dump'
}

endFold 'install-atom'

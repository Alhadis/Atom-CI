#!/usr/bin/env pwsh

if($null -eq $env:ATOM_PATH){
	Set-StrictMode -Version Latest
	$ErrorActionPreference = "Stop"
	Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
	$VerbosePreference = "Continue"
	switchToProject
	setupEnvironment
}

# Display version info for Atom/Node/?PM
function showVersions(){
	param ([Switch] $all)
	Write-Host "Printing version info..."
	cmd "$env:ATOM_SCRIPT_PATH" --version | Out-String
	cmd "$env:APM_SCRIPT_PATH"  --version --no-color
	if(-not $all){ return }
	cmd node --version
	cmd npm --version
}

# Retrieve a HashTable of version strings containing APM's version info
function getAPMVersion(){
	$versions = @{}
	$CR = [char]0x0D
	$LF = [char]0x0A
	((& "$env:APM_SCRIPT_PATH" --version --no-color) -replace "$CR$LF", "$LF") -split $LF | % {
		$line  = $_ -split " "
		$key   = $line[0].trim()
		$value = ($line[1..($line.length - 1)] -join " ").trim()
		$versions[$key] = $value
	}
	$versions
}

# Determine whether this version of APM supports the `ci`
# subcommand, which was added in atom/apm@2a6dc13 (v2.1.0).
function apmHasCI(){
	$version = (getAPMVersion).apm -split "\."
	$major   = [int] $version[0]
	$minor   = [int] $version[1]
	($major -gt 2) -or ($major -eq 2 -and $minor -ge 1)
}

# Install packages with `apm`
function apmInstall(){
	endFold "installers"
	startFold "install-deps" "Installing dependencies"
	$fix = '(\e\[\d[;\d]*m[^[:cntrl:][:blank:]]+)(\r?\n)([^\r\n]*)\k<2>?$'
	if((isFile "package-lock.json") -and (apmHasCI)){
		ul "Installing from {0}" 'package-lock.json'
		(cmd "$env:APM_SCRIPT_PATH" ci @args | Out-String | gsub $fix '$1$3$2').trim()
	}
	else{
		ul "Installing from {0}" 'package.json'
		(cmd "$env:APM_SCRIPT_PATH" install @args | Out-String | gsub $fix '$1$3$2').trim()
		(cmd "$env:APM_SCRIPT_PATH" clean         | Out-String | gsub $fix '$1$3$2').trim()
	}
}

startFold "installers" "Resolving installers"

# Run tests against bundled versions of Node
if($env:ATOM_LINT_WITH_BUNDLED_NODE -ne "false"){
	Write-Host "Using bundled version of Node"
	setEnv "ATOM_LINT_WITH_BUNDLED_NODE" "true"
	
	# Update search path to prioritise bundled executables
	$dir = "$env:ATOM_PATH/$env:ATOM_APP_NAME"
	if     ($IsMacOS)  { setEnv "PATH" "$dir/Contents/Resources/app/apm/bin:$env:PATH" }
	elseif ($IsLinux)  { setEnv "PATH" "$dir/usr/share/$env:ATOM_SCRIPT_NAME/resources/app/apm/bin:$env:PATH" }
	elseif ($IsWindows){ setEnv "PATH" "$dir\resources\app\apm\bin;$env:PATH"}
	
	showVersions
	apmInstall
}

# Run tests against system's version of NPM
else{
	Write-Host "Using system versions of Node/NPM"
	setEnv "NPM_SCRIPT_PATH" "npm"
	showVersions -all
	apmInstall --production
	cmd npm install
}

# Install other packages which this package depends on
if($env:APM_TEST_PACKAGES){
	startFold "install-package-deps" "Installing package dependencies"
	($env:APM_TEST_PACKAGES.trim()) -split '\s+' | % {
		cmd "$env:APM_SCRIPT_PATH" install $_
	}
	endFold
}

endFold "install-deps"

#!/usr/bin/env pwsh

if($null -eq $env:ATOM_PATH){
	Set-StrictMode -Version Latest
	$ErrorActionPreference = "Stop"
	Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
	$VerbosePreference = "Continue"
	assertValidProject
	setupEnvironment
}

title "Running tasks"
$use = $null -ne $env:ATOM_CI_USE_PACKAGE_SCRIPTS


# Run "lint" script if one exists in `package.json`
if($use -and (haveScript "lint")){
	runScript "lint"
}
# If not, use assumed defaults
else{
	foreach($linter in "coffeelint", "eslint", "tslint"){
		if(-not (haveDep $linter)) { continue }
		Write-Host "Linting package with $linter..."
		for($dir -in "lib", "src", "spec", "test"){
			if(isDir $dir){
				cmd "npx" $linter $dir
			}
		}
	}
}


# Run the `package.json` "test" script if one exists
if($use -and (haveScript "test")){
	runScript "test"
}
else{
	foreach($dir in "spec", "specs", "test", "tests"){
		if(isDir $dir){
			Write-Host "Running specs..."
			cmd "$env:ATOM_SCRIPT_PATH" --test $dir 2>&1 | % { "$_" }
			break
		}
	}
}

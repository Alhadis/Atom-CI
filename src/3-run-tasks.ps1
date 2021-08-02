#!/usr/bin/env pwsh

if($null -eq $env:ATOM_PATH){
	Set-StrictMode -Version Latest
	$ErrorActionPreference = "Stop"
	Import-Module -Name (Join-Path $PSScriptRoot "0-shared.psm1")
	$VerbosePreference = "Continue"
	switchToProject
	setupEnvironment
}

# Locate a project configuration file
function findConfig(){
	param ($filename, $searchPaths = @("."))
	Write-Verbose "Searching for project's $filename file..."
	foreach($path in $searchPaths){
		$config = Join-Path $path $filename
		if(isFile $config){
			$config = Resolve-Path $config
			"Using config: {0}[4m$path{0}[24m" -f [char]0x1B | Write-Verbose
			return $config.path
		}
	}
}

# Lint package source with the given linter, if it appears to be used
function runLinter(){
	param (
		[Parameter(Position = 0, Mandatory = $true)] [String] $linter,
		[Parameter(Position = 1, ValueFromRemainingArguments)] [String[]] $params
	)
	if(-not (haveDep $linter)){ return }
	Write-Host "Linting package with $linter..."
	cmd -noExit "npx" $linter @params
	if($LASTEXITCODE -ne 0){
		$script:lintResult = $LASTEXITCODE
	}
}


title "Running tasks"

# Most recent non-zero exit code returned by a linter
$script:lintResult = 0

# Candidate directories containing tests to run and/or source to lint
$script:testDirs = "spec", "specs", "test", "tests"
$script:lintDirs = @("lib", "src") + $testDirs

# Lint source directories
$dirs = Get-ChildItem -Directory | Where-Object {$_.name -in $script:lintDirs}
if($null -ne $dirs){
	
	# Shorten directory paths because
	# a) CoffeeLint can't grok absolute paths
	# b) The commands yield more readable feedback when echoed
	$dirs = $dirs | ForEach-Object { shortenPath $_ }
	
	# HACK: PowerShell v5.1 thinks splatting ["foo"] should yield "f", "o", "o"
	switch($dirs.getType().name){
		"String"   {$dirs = @($dirs)}
		"FileInfo" {$dirs = @($dirs)}
	}
	
	runLinter "coffeelint" "-q" @dirs
	runLinter "eslint" "--no-error-on-unmatched-pattern" @dirs
	
	# TSLint is "special", apparently
	if(haveDep "tslint"){
		$params = $null
		$config = findConfig "tsconfig.json"
		if(isFile $config){
			$params = "-p", $config
		}
		elseif($config = findConfig "tslint.json"){
			$root = [System.IO.Path]::GetDirectoryName($config)
			$params = Get-ChildItem $root -Recurse -File -Filter "*.ts"
		}
		if($params){
			runLinter "tslint" @params
		}
	}
	
	# Make sure all linters have finished running before terminating
	if($script:lintResult -ne 0){
		exit $script:lintResult
	}
}


# Run specs in the first known test directory that exists
$dir = Get-ChildItem -Directory `
| Where-Object {$_.name -in $script:testDirs} `
| Select-Object -First 1

if($dir){
	Write-Host "Running specs..."
	
	# HACK: Using `cmd` to invoke Atom doesn't work on Windows. I've NFI why
	Invoke-Command {cmdfmt @args} -ArgumentList @($env:ATOM_EXE_PATH, '--test', $dir | argfmt)
	& $env:ATOM_EXE_PATH --test $dir 2>&1 | % { "$_" }
	
	# Finish with an appropriate exit code
	if($LASTEXITCODE -ne 0){
		exit $LASTEXITCODE
	}
}

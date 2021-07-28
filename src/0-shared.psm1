# Display a coloured marker to demarcate logical sections of output
function title(){
	param ([Parameter(Mandatory)] [String] $text)
	$text = "{0}[1m$text{0}[22m" -f [char]0x1B
	Write-Host -NoNewline "==> " -ForegroundColor Blue
	Write-Host $text
}

# Quote a command-line argument for console display
function argfmt(){
	process {
		if($_ -match '^(?![~#\[])[-+#:@^~\w\\/\[\].]+$'){ return $_ }
		if(-not $_.contains("'")){ return "'$_'" }
		'"' + ($_ -replace '[$"`@]', '`$&') + '"'
	}
}

# Embellish and echo a command that's about to be executed
function cmdfmt(){
	if($env:GITHUB_ACTIONS){
		$argv = ($args | argfmt) -join " "
		"[command]{0}" -f "$argv" | Write-Host
		return
	}
	$ps = if($IsWindows){">"} else{"$"}
	Write-Host -NoNewline -ForegroundColor DarkGreen $ps
	$args | ForEach-Object {
		Write-Host -NoNewline " "
		$arg = $_ | argfmt
		if($arg -ceq $_){
			Write-Host -NoNewline -ForegroundColor Green $arg
		}
		else{
			Write-Host -NoNewline -ForegroundColor DarkGreen $arg[0]
			Write-Host -NoNewline -ForegroundColor Green     $arg.substring(1, $arg.length - 2)
			Write-Host -NoNewline -ForegroundColor DarkGreen $arg[-1]
		}
	}
	Write-Host ""
}

# Print a command before executing it
function cmd(){
	param (
		[Parameter(HelpMessage = "Don't terminate upon exiting with an error code")] [Switch] $noExit,
		[Parameter(Position = 0, Mandatory = $true)] [String] $name,
		[Parameter(Position = 1, ValueFromRemainingArguments)] [String[]] $argv
	)
	cmdfmt $name @argv
	
	# HACK: Fix double-quote stripping
	if("AZ" -eq (& node -p "'A`"Z'")){
		$argv = $argv.forEach{$_ -replace '"', '"""'}
	}
	& "$name" @argv
	
	# Handle non-zero exit codes manually
	if((-not $noExit) -and ($LASTEXITCODE -ne 0)){
		exit $LASTEXITCODE
	}
}

# Return true if a path exists on disk
function exists(){
	param ($path)
	Test-Path -Path $path
}

# Return true if a path references a directory
function isDir(){
	param ($path)
	Test-Path -Path $path -PathType Container
}

# Return true if a path references an ordinary file
function isFile(){
	param ($path)
	Test-Path -Path $path -PathType Leaf
}

# Terminate the running script with an error message
function die(){
	param ($message = "", $code = 1)
	Write-Host $message
	$host.SetShouldExit($code)
	Exit $code
}

# Replace all occurrences of a pattern in a string
function gsub(){
	param($regex, $replacement = "", $options = 0)
	begin{
		$opts    = [Text.RegularExpressions.RegexOptions]
		$options = ($options -as $opts) -bor ("CultureInvariant, Multiline" -as $opts)
	}
	process{
		[Regex]::Replace($_, $regex, $replacement, $options)
	}
}

# Delete a file or directory indiscriminately
function rmrf(){
	param ($path)
	if(exists($path)){
		Write-Verbose "Removing $path"
		Remove-Item -Recurse -ErrorAction Ignore $path
	}
}

# Create a directory and any intermediate parent directories
function mkdirp(){
	param ($path)
	$segments = ($path -replace "/", [char]0x5C) -split "\\"
	$absolute = Split-Path -Path $path -IsAbsolute
	$path = "."
	if($absolute){
		$path = "/"
		if($IsWindows){
			$drive    = $segments[0] + "/"
			$segments = $segments[1..($segments.count - 1)]
			$path     = $drive + $path
		}
	}
	foreach($segment in $segments){
		$path = Join-Path $path $segment
		if(-not(exists $path)){
			Write-Verbose "Creating directory: $path"
			New-Item -Type Directory $path > $null
		}
		elseif(-not(isDir $path)){
			Write-Error "Not a directory: $path"
			break
		}
	}
}

# Convert an absolute path to a relative one if possible
function shortenPath(){
	param (
		[Parameter(Mandatory = $true, HelpMessage = "Filesystem path to shorten")]
		[String] $path,
		
		[Parameter(HelpMessage = "Don't shorten paths located above current directory.")]
		[Switch] $noParents,
		
		[Parameter(HelpMessage = "Don't prefix child directories with './' or '.\'")]
		[Switch] $noPrefix
	)
	$sep = [System.IO.Path]::DirectorySeparatorChar
	$abs = [System.IO.Path]::IsPathRooted($path)
	$cwd = (Get-Location).toString()
	
	# Trim trailing path separator
	if(($path.length -gt 0) -and (-not $abs) -and ($sep -eq $path[-1])){
		$path = $path.substring(0, $path.length - 1)
	}
	
	# Truncate absolute paths if doing so incurs no loss of ambiguity
	if($abs){
		if($path -eq $home){ return "~" }
		if($path -eq $cwd) { return "." }
		if($path.startsWith($cwd + $sep)){
			if($noPrefix){ return $path.substring($cwd.length + 1) }
			return "." + $path.substring($cwd.length)
		}
		if($path.startsWith($home + $sep)){
			return "~" + $path.substring($home.length)
		}
	}
	if($null -ne ([System.IO.Path] | Get-Member -static "GetRelativePath")){
		$rel = [System.IO.Path]::GetRelativePath($cwd, $path)
		if($noParents -and ($rel -eq ".." -or $rel.startsWith("..$sep")))   { return $path }
		if($noPrefix -and ($rel.length -gt 2) -and $rel.startsWith(".$sep")){ $rel = $rel.substring(2) }
		return $rel
	}
	$path
}

# Set the default output encoding to UTF-8
function setEncoding(){
	param ($encoding = "UTF8")
	$enc = [System.Text.Encoding]
	if($encoding -isnot $enc){ $encoding = $enc::$encoding }
	[Console]::OutputEncoding = $encoding
	$OutputEncoding           = $encoding
}

# List environment variables
function dumpEnv(){
	$env = [Environment]::GetEnvironmentVariables()
	$env.keys | Sort-Object | % {
		[PSCustomObject] @{ Name = $_; Value = $env[$_] }
	} | Format-Table -Wrap
}

# Set the value of an environment variable
function setEnv(){
	param ([Parameter(Mandatory = $true)] [String] $name, $value = "", [Switch] $default)
	if($default -and ($null -ne [Environment]::GetEnvironmentVariable($name))){ return }
	if($value -eq $null){ return unsetEnv $name }
	$value = [String] $value
	Write-Verbose "Environment variable $name set to $value"
	New-Variable -Name "env:$name" -Value $value -Scope "Global" -Visibility "Public"
	[Environment]::SetEnvironmentVariable($name, $value, "Process")
}

# Delete an environment variable
function unsetEnv(){
	param ($name)
	if($null -eq [Environment]::GetEnvironmentVariable($name)){ return }
	Write-Verbose "Unsetting environment variable $name"
	Remove-Variable -Name "env:$name" -Scope "Global" -Force
	[Environment]::SetEnvironmentVariable($name, $null)
}

# Extract the contents of a ZIP archive
function unzip(){
	param ($archive, $destination = ".", [Switch] $noOverwrite)
	
	# Expand relative paths to absolute ones
	$us  = [char]0x1B + "[4m"
	$ue  = [char]0x1B + "[24m"
	$cwd = Get-Location
	if(-not (Split-Path -Path $archive     -IsAbsolute)){ $archive     = Join-Path $cwd $archive }
	if(-not (Split-Path -Path $destination -IsAbsolute)){ $destination = Join-Path $cwd $destination }
	if($noOverwrite -and (isDir $destination) -and ($cwd -ne (Resolve-Path $destination))){
		Write-Host "Extraction directory $us$destination$ue already exists, skipping"
		return
	}
	Write-Host "Extracting $us$archive$ue to $us$destination$ue..."
	
	# Delete and recreate target directory
	Remove-Item -Recurse -Force -ErrorAction Ignore $destination
	mkdirp $destination
	
	if($IsWindows){
		Add-Type -AssemblyName System.IO.Compression.FileSystem
		[System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $destination)
	}
	# Use unzip(1) because PowerShell's `ZipFile` doesn't grok symlinks
	else{
		$unzip = which "unzip"
		if($null -eq $unzip){
			die "Unzip utility required to unpack archive containing symlinks"
		}
		$flags = "-oq"
		if($noOverwrite){ $flags = "-nq" }
		cmd "$unzip" "$flags" $archive "-d" $destination
	}
}

# Locate an executable in the user's search-path
function which(){
	param ([String] $name)
	try{
		$cmd = Get-Command -commandType Application -totalCount 1 $name
		return $cmd.source
	} catch { return $null }
}

# Download a web resource
function fetch(){
	param ($url, $headers = @{})
	Write-Verbose "Downloading: $url"
	$ProgressPreference = "SilentlyContinue"
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::TLS12
	Invoke-WebRequest -URI $url -UseBasicParsing -Headers $headers
}

# Convert a date object to the format frequently used in temporal HTTP headers (see RFC 1123)
function formatHTTPDate(){
	param ([Parameter(
		Mandatory = $true,
		Position = 0,
		ValueFromPipeline = $true,
		ValueFromPipelineByPropertyName = $true
	)] [DateTime] $date)
	begin   { $culture = [System.Globalization.CultureInfo]::InvariantCulture }
	process { $date.toString("ddd, dd MMM yyyy HH:mm:ss", $culture) + " GMT" }
}

# Convert a PSCustomObject to a HashTable
function convertObjectToHash(){
	param ($subject, [HashTable] $refs = @{})
	if($refs.containsKey($subject)){
		return $refs[$subject]
	}
	$hash = @{}
	$refs[$subject] = $hash
	$subject.psobject.properties | % {
		$key   = $_.name
		$value = $_.value
		if($value -is [PSCustomObject]){
			$converted = convertObjectToHash $value $refs
			$refs[$value] = $converted
			$value = $converted
		}
		$hash[$key] = $value
	}
	$hash
}


$script:jsonCache = @{}

# Load and parse a JSON file, with the results cached to quicken future lookups
function json(){
	param ($path)
	$path = (Resolve-Path $path).toString()
	if($script:jsonCache.contains($path)){
		Write-Verbose "Reusing cached contents of $path"
		return $script:jsonCache[$path]
	}
	$json = Get-Content $path
	if((Get-Command ConvertFrom-JSON).Parameters.containsKey("AsHashTable")){
		$json = $json | ConvertFrom-JSON -AsHashTable
	}
	else{
		$json = convertObjectToHash ($json | ConvertFrom-JSON)
	}
	$script:jsonCache[$path] = $json
	$json
}

# Currently-open folds
$script:folds = [System.Collections.ArrayList]::new()

# Begin a collapsible folding region
function startFold(){
	param ([String] $id, [String] $label = "")
	if($env:TRAVIS_JOB_ID){
		$text = "travis_fold:start:$id{0}{1}[0K" -f [char]0x0D, [char]0x1B
		Write-Host -NoNewline $text
	}
	elseif($env:GITHUB_ACTIONS -and $label){
		if($script:folds.Add($id) -eq 0){
			Write-Host "::group::$label"
			return
		}
	}
	title $label
}

# Close a collapsible folding region
function endFold(){
	param ($id)
	if($env:TRAVIS_JOB_ID){
		$text = "travis_fold:end:$id{0}{1}[0K" -f [char]0x0D, [char]0x1B
		Write-Host -NoNewline $text
	}
	elseif($env:GITHUB_ACTIONS -and $script:folds.Count -gt 0){
		if($null -eq $id){
			$id = $script:folds[-1]
		}
		elseif(-not $script:folds.Contains($id)){
			Write-Warning "No such fold: $id"
			return
		}
		$index = $script:folds.indexOf($id)
		$count = $script:folds.count - $index
		$script:folds.removeRange($index, $count)
		if($script:folds.count -eq 0){
			Write-Host "::endgroup::"
		}
	}
}

# Abort script if current directory lacks a test directory and `package.json` file
function assertValidProject(){
	if(-not(isFile "package.json")){
		die 'No package.json file found'
	}
	if((Get-ChildItem "package.json").length -eq 0){
		die 'package.json appears to be empty'
	}
	foreach($dir in "spec", "specs", "test", "tests"){
		if(isDir($dir)){ return }
	}
	die 'Project must contain a test directory'
}

# Check if a development dependency is listed in a project's `package.json` file
function haveDep(){
	param ($name)
	$pkg = json "package.json"
	foreach($key in "devDependencies", "dependencies"){
		if($pkg.contains($key) -and $pkg[$key].contains($name)){
			return $true
		}
	}
	return $false
}

# Retrieve the tag-name for the latest Atom release
function getLatestRelease(){
	[OutputType([String])]
	param ($betaChannel = $false)
	if($null -eq $betaChannel){ $betaChannel = $false }
	[xml]$releases = fetch "https://github.com/atom/atom/releases.atom"
	($releases.feed.entry `
	| Where-Object {$betaChannel -eq ($_.title -match "-beta")} `
	| Sort-Object -Property "Updated" -Descending `
	| Select-Object -Index 0
	).link.href
}

# Download an Atom release
function downloadAtom(){
	[CmdletBinding(DefaultParameterSetName = "Tag")]
	param (
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Tag",
			HelpMessage = "Enter the name of a tagged release",
			Position = 0
		)] [String] $release,
		
		[Parameter(
			Mandatory = $true,
			ParameterSetName = "Channel",
			HelpMessage = "Specify a release channel",
			Position = 0
		)] [String] [ValidateSet("stable", "beta")] $channel,
		
		[Parameter(ParameterSetName = "Tag")]
		[Parameter(ParameterSetName = "Channel")]
		[Alias("IfNeeded")]
		[Switch] $reuseExisting,
		
		[Parameter(Position = 1, ParameterSetName = "Tag")]
		[Parameter(Position = 1, ParameterSetName = "Channel")]
		[String] $assetName,
		
		[Parameter(Position = 2, ParameterSetName = "Tag")]
		[Parameter(Position = 2, ParameterSetName = "Channel")]
		[String] $saveAs = $assetName
	)
	
	# Resolve the latest release published to the specified channel
	if($channel){
		$isBeta  = $channel.tolower() -eq "beta"
		$release = getLatestRelease $isBeta
		$release = [URI]::new($release).segments[-1]
	}
	
	# Reuse an earlier download if one exists
	if($reuseExisting -and (isFile $saveAs)){
		"Already downloaded: {0}[4m$saveAs{0}[24m" -f [char]0x1B | Write-Host
		return
	}
	
	# Resolve the URL from which to download
	foreach($link in (fetch "https://github.com/atom/atom/releases/tag/$release").links){
		$url = $link.href `
		| gsub "^(?!\w+?://?)/{0,2}" "https://github.com/" `
		| gsub "#.*"
		
		if($url -match "^https://github\.com/.*/$release/$assetName(?:$|\?)"){
			"Downloading Atom $release from {0}[4m$url{0}[24m" -f [char]0x1B | Write-Host
			Invoke-WebRequest -URI $url -UseBasicParsing -OutFile $saveAs -Headers @{
				Accept = "application/octet-stream"
			} > $null
			return
		}
	}
	throw "Failed to resolve asset URL"
}

# Setup environment variables
function setupEnvironment(){
	$folded = $false
	if($VerbosePreference -in "Continue", "Inquire"){
		startFold "setup-env" "Resolving environment variables"
		$folded = $true
	}
	
	# Set some reasonable defaults for an Atom project
	setEnv -default "ELECTRON_NO_ATTACH_CONSOLE" "true"
	setEnv -default "ELECTRON_ENABLE_LOGGING" $null
	setEnv -default "NODE_NO_WARNINGS" 1

	# Resolve what version of Atom we're downloading
	if($env:ATOM_RELEASE){
		$channel = "stable"
		if($env:ATOM_RELEASE -match "-beta"){
			$channel = "beta"
		}
		setEnv "ATOM_CHANNEL" $channel
	}
	else{
		if(-not $env:ATOM_CHANNEL){
			setEnv "ATOM_CHANNEL" "stable"
		}
		elseif(-not $env:ATOM_CHANNEL -in "beta", "stable"){
			die "Unsupported channel: $env:ATOM_CHANNEL"
		}
	}

	# Windows
	if($IsWindows){
		$assetName  = "atom-windows.zip"
		$appName    = "Atom"
		$scriptName = "atom"
		if($env:ATOM_CHANNEL -eq "beta"){
			$appName    = "Atom Beta"
			$scriptName = "atom-beta"
		}
		$atomPath   = Join-Path (Get-Location) "_atom-ci"
		$scriptPath = "$atomPath\$appName\resources\cli\atom.cmd"
		$apmPath    = "$atomPath\$appName\resources\app\apm\bin\apm.cmd"
		$npmPath    = "$atomPath\$appName\resources\app\apm\node_modules\.bin"
		setEnv "PATH" "$npmPath;${env:PATH}"
		setEnv "ATOM_EXE_PATH" "$atomPath\$appName\$scriptName.exe"
		$npmPath += "\npm.cmd"
	}
	# macOS/Darwin
	elseif($IsMacOS){
		$assetName = "atom-mac.zip"
		$appName   = "Atom.app"
		if($env:ATOM_CHANNEL -eq "beta"){
			$appName = "Atom Beta.app"
		}
		$atomPath   = Join-Path (Get-Location) ".atom-ci"
		$scriptName = "atom.sh"
		$scriptPath = "$atomPath/$appName/Contents/Resources/app/$scriptName"
		$binPath    = "$atomPath/$appName/Contents/Resources/app/apm/node_modules/.bin"
		$apmPath    = "$binPath/apm"
		$npmPath    = "$binPath/npm"
		setEnv "PATH" "${binPath}:${env:PATH}"
		setEnv "ATOM_APP_NAME" $appName
		setEnv "ATOM_EXE_PATH" $scriptPath
	}
	# Linux (Debian assumed)
	elseif($IsLinux){
		$assetName  = "atom-amd64.deb"
		$scriptName = "atom"
		$apmName    = "apm"
		if($env:ATOM_CHANNEL -eq "beta"){
			$scriptName = "atom-beta"
			$apmName    = "apm-beta"
		}
		$atomPath   = Join-Path (Get-Location) ".atom-ci"
		$scriptPath = "$atomPath/usr/bin/$scriptName"
		$apmPath    = "$atomPath/usr/bin/$apmName"
		$npmPath    = "$atomPath/usr/share/$scriptName/resources/app/apm/node_modules/.bin"
		setEnv "PATH" "$atomPath/usr/bin:${npmPath}:${env:PATH}"
		setEnv "APM_SCRIPT_NAME" $apmName
		$npmPath += "/npm"
	}
	# Unsupported platform (shouldn't happen)
	else{
		$os = [System.Environment]::OSVersion.Platform
		die "Unsupported platform: $os" 2
	}
	
	setEnv "ATOM_ASSET_NAME"  $assetName
	setEnv "ATOM_PATH"        $atomPath
	setEnv "ATOM_SCRIPT_NAME" $scriptName
	setEnv "ATOM_SCRIPT_PATH" $scriptPath
	setEnv "APM_SCRIPT_PATH"  $apmPath
	setEnv "NPM_SCRIPT_PATH"  $npmPath

	if($folded){
		endFold "setup-env"
	}
}

# Ensure these variables are defined for older versions of PowerShell
try{
	Get-Variable $IsWindows >$null
	Get-Variable $IsMacOS   >$null
	Get-Variable $IsLinux   >$null
}
catch{
	$unix = [System.Environment]::OSVersion.Platform -like "Unix*"
	New-Variable -Name "IsWindows" -Scope "Global" -Option ReadOnly,AllScope -Visibility "Public" -Value (-not $unix)
	New-Variable -Name "IsLinux"   -Scope "Global" -Option ReadOnly,AllScope -Visibility "Public" -Value $unix
	New-Variable -Name "IsMacOS"   -Scope "Global" -Option ReadOnly,AllScope -Visibility "Public" -Value $false
}

# Fix display of Unicode characters
setEncoding "UTF8"

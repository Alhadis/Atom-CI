# Display a coloured marker to demarcate logical sections of output
function title(){
	param ([Parameter(Mandatory)] [String] $text)
	$text = "{0}[1m$text{0}[22m" -f [char]0x1B
	Write-Host -NoNewline "==> " -ForegroundColor Blue
	Write-Host $text
}

# Embellish and echo a command that's about to be executed
function cmdfmt(){
	$name = $args[0]
	$argv = $args[1..($args.length - 1)]
	$ps = "$"
	if($IsWindows){ $ps = ">" }
	Write-Host -NoNewline -ForegroundColor DarkGreen $ps
	Write-Host -NoNewline -ForegroundColor Green " $name"
	foreach($arg in $argv){
		if($arg -match '^(?![~#])[-+#:@^~\w]+$'){
			Write-Host -NoNewline -ForegroundColor Green " $arg"
		}
		else{
			Write-Host -NoNewline -ForegroundColor DarkGreen ' "'
			Write-Host -NoNewline -ForegroundColor Green     "$arg"
			Write-Host -NoNewline -ForegroundColor DarkGreen '"'
		}
	}
	Write-Host ""
}

# Print a command before executing it
function cmd(){
	$name = $args[0]
	$argv = $args[1..($args.length - 1)]
	cmdfmt $name @argv
	
	# HACK: Fix double-quote stripping
	if("AZ" -eq (& node -p "'A`"Z'")){
		$argv = $argv.forEach{$_ -replace '"', '"""'}
	}
	& "$name" @argv
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
	if($absolute){ $path = "/" }
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

# Set the value of an environment variable
function setEnv(){
	param ($name, $value = "")
	Write-Verbose "Environment variable $name set to $value"
	New-Variable -Name "env:$name" -Value $value -Scope "Global" -Visibility "Public"
	[Environment]::SetEnvironmentVariable($name, $value, "Process")
}

# Extract the contents of a ZIP archive
function unzip(){
	param ($archive, $destination = ".")
	Write-Verbose "Extracting $archive to $destination"
	mkdirp $destination
	[System.IO.Compression.ZipFile]::ExtractToDirectory($archive, $destination, $true)
}

# Download a web resource
function fetch(){
	param ($url, $headers = @{})
	Write-Verbose "Downloading: $url"
	$ProgressPreference = "SilentlyContinue"
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
	$culture = [System.Globalization.CultureInfo]::InvariantCulture
	$date.toString("ddd, dd MMM yyyy HH:mm:ss", $culture) + " GMT"
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
	$json = Get-Content $path | ConvertFrom-JSON -AsHashTable
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
		if($id -eq $null){
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
	$pkg.contains("devDependencies") -and $pkg.devDependencies.contains($name)
}

# Check if a project's `package.json` file defines a script with the given name
function haveScript(){
	param ($name)
	$pkg = json "package.json"
	$pkg.contains("scripts") -and $pkg.scripts.contains($name)
}

# Retrieve the tag-name for the latest Atom release
function getLatestRelease(){
	[OutputType([String])]
	param ($betaChannel = $false)
	[xml]$releases = fetch "https://github.com/atom/atom/releases.atom"
	($releases.feed.entry
	| Where-Object {$betaChannel -eq ($_.title -match "-beta")}
	| Sort-Object -Property "Updated" -Descending
	| Select-Object -Index 0
	).link.href
}

# Extract a list of HREF attributes from HTML source
function extractLinks(){
	param ($hostname = "")

	# Normalise hostname, if provided
	if($hostname){
		$hostname = $hostname
		| gsub "^(?![-\w]+:)" "https://"
		| gsub "(https?)://?" '$1://' "IgnoreCase"
		| gsub "/+$"
	}
	
	# Normalise attribute casing and quoting
	$html = $input
	| gsub "(?i)(\s+|^)href\s*=\s*" " href="
	| gsub "href=\s*([^""'\s<>]+)" 'href="$1"'
	| gsub "href='([^'<>]*)'" 'href="$1"'
	
	# Retrieve all non-blank HREF attributes
	[Regex]::Matches($html, ' href="([^"<>]+)"') | ForEach-Object {
		$_.Groups[-1].value
		| gsub "&amp;"  "&"
		| gsub "&quot;" '"'
		| gsub "&lt;"   "<"
		| gsub "&gt;"   ">"
		| gsub "^(?!\w+?://?)/{0,2}" "$hostname/"
	}
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
	
	# Resolve the URL from which to download
	$url = fetch "https://github.com/atom/atom/releases/tag/$release"
	| extractLinks "github.com"
	| Where-Object { $_ -match "/$release/$assetName" }
	| Select-Object -Index 0
	
	# Reuse an earlier download if one exists
	if($reuseExisting -and (isFile $saveAs)){
		"Already downloaded: {0}[4m$saveAs{0}[24m" -f [char]0x1B | Write-Host
		return
	}
	
	# Otherwise, start downloadin'
	"Downloading Atom $release from {0}[4m$url{0}[24m" -f [char]0x1B | Write-Host
	Invoke-WebRequest -URI $url -UseBasicParsing -OutFile $saveAs -Headers @{
		Accept = "application/octet-stream"
	} > $null
}

# Setup environment variables
function setupEnvironment(){
	$folded = $false
	if($VerbosePreference -in "Continue", "Inquire"){
		startFold "setup-env" "Resolving environment variables"
		$folded = $true
	}
	
	setEnv "ELECTRON_NO_ATTACH_CONSOLE" "true"
	setEnv "ELECTRON_ENABLE_LOGGING" "YES"

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
		$scriptPath = "$atomPath\$appName\resources\cli\$scriptName.cmd"
		$apmPath    = "$atomPath\$appName\resources\app\apm\bin\apm.cmd"
		$npmPath    = "$atomPath\$appName\resources\app\apm\node_modules\.bin\npm.cmd"
		setEnv "ATOM_EXE_PATH" "$atomPath\$appName\$scriptName.exe"
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
		$apmPath    = "$atomPath/$appName/Contents/Resources/app/apm/node_modules/.bin/apm"
		$npmPath    = "$atomPath/$appName/Contents/Resources/app/apm/node_modules/.bin/npm"
		setEnv "PATH" "${env:PATH}:$atomPath/$appName/Contents/Resources/app/apm/node_modules/.bin"
		setEnv "ATOM_APP_NAME" $appName
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
		setEnv "PATH" "${env:PATH}:$atomPath/usr/bin:$npmPath"
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
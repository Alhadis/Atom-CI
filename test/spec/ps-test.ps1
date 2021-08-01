#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module -force -name (Join-Path $PSScriptRoot "../../src/0-shared.psm1")

# Underlines
ul "./path/to/some thing"
ul "{0} -> {1}" "/usr/local/opt/bin/dest" "./link"

"./path/to/some thing", "/another/path" | ul
"{0} -> {1}" -f "/usr/local/opt/bin/dest", "./link" | ul


# Warnings and errors
warn "This {0} is {1}" "warning" "stupid"
err  "This {0} is {1}" "error" "even stupider"

"This {0} is also {1}" -f "warning", "stupid"      | ul | warn
"This {0} is also {1}" -f "error", "even stupider" | ul | err


# Even more warnings and errors
"Message text: {0} {1}" -f "Foo", "Bar" | warn
warn "Message text: {0} {1}" "Foo" "Bar"
warn "Message text: {0}"     "Foo"
warn "Message text: {0}"
Get-ChildItem | warn

"Message text: {0} {1}" -f "Foo", "Bar" | err
err "Message text: {0} {1}" "Foo" "Bar"
err "Message text: {0}"     "Foo"
err "Message text: {0}"
Get-ChildItem | err

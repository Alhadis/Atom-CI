#
# Use production-ready settings for distributed PowerShell script:
# always re-download releases, and overwrite files when unzipping.
#
# The PowerShell source files assume the developer is hacking on
# them locally, and as such, will avoid redownloading assets for
# efficiency. In a production environment (such as a CI server),
# this behaviour can lead to non-determinism.
#

/^[[:blank:]]*unzip / {
	s/[[:blank:]]-[Nn][Oo][Oo][Vv][Ee][Rr][Ww][Rr][Ii][Tt][Ee]/ -noOverwrite/g
	s/ -noOverwrite$//
	s/-noOverwrite / /g
	s/^\([[:blank:]]*unzip[[:blank:]]\{1,\}\)\$env:ATOM_ASSET_NAME[[:blank:]]/\1"atom.zip" /
}

/^[[:blank:]]*downloadAtom / {
	s/[[:blank:]]-[Rr][Ee][Uu][Ss][Ee][Ee][Xx][Ii][Ss][Tt][Ii][Nn][Gg]/ -reuseExisting/g
	s/ -reuseExisting$//
	s/-reuseExisting / /g
	s/$/ -saveAs "atom.zip"/
}

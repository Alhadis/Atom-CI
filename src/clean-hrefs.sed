#
# Normalises different permutations of HTML attribute formatting
# for `href` attributes. This enables us to accurately match links
# irrespective of intermediate whitespace, casing, or quote-style:
#
#    <a href = 'http://url'></a>
#    <A HREF = http://url></a>
#    <a hReF
#         = "http://url"></a>
#
# Each of the above examples will be normalised to
#
#    <a href="http://url"></a>
#
# so an otherwise naïve pattern like this will match reliably:
#
#    /href="([^"]*)"/
#
# An uncommented version of this is embedded in `cleanHrefs()`
# (declared in `./0-shared.sh`). This copy exists mainly for
# pedagogical reasons.
#

# 1. Start-of-file
:x

# 2. Collapse newlines between `href` and `=`
/[Hh][Rr][Ee][Ff][[:blank:]]*$/,/=/ {
	N
	s/\n//g
	
	# Loop back to step 1.
	bx
}

# 3. Strip blanks before `=`, and force lowercase attribute-names
s/[Hh][Rr][Ee][Ff][[:blank:]]*=/href=/g

# 4. Collapse newlines between `href=` and the value that follows
/href=[[:blank:]]*$/ {
	N
	s/\n//g
	
	# Loop back to step 1.
	bx
}

# 5. href='single-quotes' => href="double-quotes"
s/href=[[:blank:]]*'\([^']*\)'/href="\1"/g

# 6. href=unquoted-values => href="quoted-values"
s/href=[[:blank:]]*\([^"'[:blank:]<>][^"'[:blank:]<>]*\)/href="\1"/g

# 7. Strip whitespace in and around unnormalised double-quoted values
s/href[[:blank:]]*=[[:blank:]]*"/href="/g

# 8. Force a leading space if attribute starts on first column of new line
s/^href=/ href=/g

# 9. Replace possible tab with a space for easier matching
s/[[:blank:]]href=/ href=/g

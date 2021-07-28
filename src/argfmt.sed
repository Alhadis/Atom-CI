#
# Format a command-line argument for terminal display
#
:x

/^[]+:@^_[:alnum:][=[=]/.-][]~#+:@^_[:alnum:][=[=]/.-]*$/! {

	# If there's only one unsafe character, don't quote: simply escape it instead
	/^[]~#+:@^_[:alnum:][=[=]/.-]*[^]~#+:@^_[:alnum:][=[=]/.-][]~#+:@^_[:alnum:][=[=]/.-]*$/ {
		
		# ... unless it's an equals-sign used like `--name=safe-chars`
		/^--*.*=/! s/[^]~#+:@^_[:alnum:][=[=]/.-]/\\&/
		
		n
		bx
	}
	
	# Enclose with 'single-quotes'
	/'/! {
		s/^/'/
		s/$/'/
		n
		bx
	}
	
	# Enclose with "double-quotes"
	s/[$"\\@]/\\&/g
	s/^/"/
	s/$/"/
}

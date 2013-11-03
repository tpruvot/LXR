#!/usr/bin/env perl -w
# Apache mod_perl additional configuration file
#
#-	$Id: apache2-require.pl,v 1.2 2013/01/11 12:06:14 ajlittoz Exp $
#-
#-
#-	This configuration file is fully configured by script
#-	configure-lxr.pl (along with all other files).
#-
#	If configured manually, it could be worth to use relative
#	file paths so that this file is location independent.
#	Relative file paths are here relative to LXR root directory.

@INC=	( @INC
		, "%LXRroot%"		# <- LXR root directory
		, "%LXRroot%/lib"	# <- LXR library directory
		);

1;

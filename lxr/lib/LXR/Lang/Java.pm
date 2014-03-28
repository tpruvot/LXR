# -*- tab-width: 4 -*-
###############################################
#
# $Id: Java.pm,v 1.12 2013/09/24 07:59:19 ajlittoz Exp $
#
# Enhances the support for the Java language over that provided by
# Generic.pm
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
###############################################

package LXR::Lang::Java;

my $CVSID = '$Id: Java.pm,v 1.12 2013/09/24 07:59:19 ajlittoz Exp $ ';

use strict;
use LXR::Common;
require LXR::Lang;
require LXR::Lang::Generic;

@LXR::Lang::Java::ISA = ('LXR::Lang::Generic');

# Only override the include handling.  For java, this is really package
# handling, as there is no include mechanism, so deals with "package"
# and "import" keywords

sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# directive name and spacing
	my $file;		# language path
	my $path;		# OS file path
	my $link;		# link to file
	my $class;		# Java class

	# Deal with package declaration of the form
	# "package java.lang.util"
	if ($source =~ s/^
				(package\s+)
				([\w.]+)	# package 'path'
				//sx) {
		$dirname = $1;
		$file    = $2;
		$path    = $file;
		$path =~ s@\.@/@g;		# Replace Java delimiters
		$link = $self->_linkincludedirs
					( &LXR::Lang::incdirref
							($file, "include", $path, $dir)
					, $file
					, '.'
					, $path
					, $dir
					);
	}

	# Deal with import declaration of the form
	# "import java.awt.*" by providing link to the package

	# Deal with import declaration of the form
	# "import java.awt.classname" by providing links to the
	# package and the class
	elsif ($source =~ s/^
				(import\s+(?:static\s+)?)
				([\w.]+)	# package 'path'
				\.(\*|\w+)	# class or *
				//sx) {
		$dirname = $1;
		$file    = $2;
		$path    = $file;
		$class   = $3;
		$path =~ s@\.@/@g;		# Replace Java delimiters
		$link = $self->_linkincludedirs
					( &LXR::Lang::incdirref
							($file, "include", $path, $dir)
					, $file
					, '.'
					, $path
					, $dir
					)
			.	'.'
			.	( $index->issymbol($class, $releaseid)
				? join($class, @{$$self{'itag'}})
				: $class
				);
	} else {
		# Guard against syntax error or variant
		# Advance past keyword, so that parsing may continue without loop.
		$source =~ s/^([\w]+)//;	# Erase keyword
		$dirname = $1;
		$link = '';
	}

	# As a goodie, rescan the tail of package/import for Java code
	&LXR::SimpleParse::requeuefrag($source);

	# Assemble the highlighted bits
	$$frag =	"<span class='reserved'>$dirname</span>"
			.	$link;
}

1;


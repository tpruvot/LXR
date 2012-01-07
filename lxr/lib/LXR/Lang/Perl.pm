# -*- tab-width: 4 -*-
###############################################
#
# $Id: Perl.pm,v 1.9 2012/01/26 16:35:35 ajlittoz Exp $
#
# Implements generic support for any language that ectags can parse.
# This may not be ideal support, but it should at least work until
# someone writes better support.
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

package LXR::Lang::Perl;

$CVSID = '$Id: Perl.pm,v 1.9 2012/01/26 16:35:35 ajlittoz Exp $ ';

use strict;
use LXR::Common;
use LXR::Lang;
require LXR::Lang::Generic;

@LXR::Lang::Perl::ISA = ('LXR::Lang::Generic');

# Process a Perl include directive
sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# include directive name
	my $spacer;		# spacing
	my $file;		# language include file
	my $path;		# OS include file
	my $link;		# link to include file

	$source =~ s/^					# reminder: no initial space in the grammar
				([\w\#]\s*[\w]*)	# reserved keyword for include construct
				(\s+)				# space
				([\w:]+)\b
				//sx ;
	$dirname = $1;
	$spacer  = $2;
	$file    = $3;
	$path    = $file;

	$path =~ s@::@/@g;
	$path =~ s@$@.pm@;
	$link = &LXR::Common::incref($file, "include" ,$path ,$dir);
	if ( defined($link)) {
		while ($file =~ m!::!) {
			$link =~ s!^([^>]+>)([^:]*::)+!$1!g;
			$file =~ s!::[^:]*$!!;
			$path =~ s!/[^/]+$!!;
			$link = &LXR::Common::incdirref($file, "include" ,$path ,$dir)
					. "::"
					. $link ;
		}
	} else {
		$link = $file;
	}
	$$frag =	"<span class='reserved'>$dirname</span>"
			.	$spacer
			.	( defined($link)
				? $link
				: $file
				)
			. $source;
}

1;

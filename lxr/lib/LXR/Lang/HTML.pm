# -*- tab-width: 4 -*-
###############################################
#
# $Id: HTML.pm,v 1.3 2013/11/08 09:04:27 ajlittoz Exp $
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
#
###############################################

=head1 HTML language module

This module is the HTML language highlighting engine.
It is driven by specifications read from file I<generic.conf>.

=cut

package LXR::Lang::HTML;

$CVSID = '$Id: HTML.pm,v 1.3 2013/11/08 09:04:27 ajlittoz Exp $ ';

use strict;
require LXR::Lang::Generic;

our @ISA = ('LXR::Lang::Generic');



=head2 C<processinclude ($frag, $dir)>

Method C<processinclude> is invoked to process an HTML I<include> directive
(aka target of an C<E<lt>AE<gt>> link or C<E<lt>IMGE<gt>> designation.

=over

=item 1 C<$frag>

a I<reference to a string> containing the directive

=item 1 C<$dir>

an optional I<string> containing a preferred directory for the include'd file

=back

Targets which obviously aren't files
(like C<http:...>) are discarded.
Since they are contained in a I<string>, they are requeued
and the eventual URLs will be highlighted by string markup.

=cut

sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# uses directive name and spacing
	my $file;		# language include file
	my $path;		# OS include file

	# Faster surrogate for 'directive'
	if ($source !~ s/^		# reminder: no initial space in the grammar
					(\w+)	# reserved keyword for include construct
					=
					("|')	# string opening delimiter
					(.+)	# file name
					\g{2}	# string closing delimiter
					//sx) {
		# Guard against syntax error or variant
		# Advance past keyword, so that parsing may continue without loop.
		$source =~ s/^(\w+)//;	# Erase keyword
		$dirname = $1;
		$$frag =	( $self->isreserved(uc($dirname))
					? "<span class='reserved'>$dirname</span>"
					: $dirname
					);
		&LXR::SimpleParse::requeuefrag($source);
		return;
	}

	$dirname = $1;
	my $delim= $2;
	$file    = $3;
	$path    = $file;
	$path =~ s/&quot;/"/g;	# replace character references in OS name
	$path =~ s/&#34/"/g;
	$path =~ s/&#39/'/g;
	$path =~ s/&#x22/"/ig;
	$path =~ s/&#x27/'/ig;

	$$frag = 	( $self->isreserved(uc($dirname))
				? "<span class='reserved'>$dirname</span>"
				: $dirname
				)
				. '=';	

	# Check for non-files (starts with scheme:)
	if ($file =~ m!^[a-zA-Z]+:!) {
		&LXR::Markup::freetextmarkup($file);
		$$frag .= '<span class="string">'
				. $delim
				. $file
				. $delim
				. '</span>';
		return;
	}

	# Create the hyperlink
	$$frag .= $delim
			. $self->_linkincludedirs
				( &LXR::Common::incref
					($file, 'include', $path, $dir)
				, $file
				, '/'
				, $path
				, $dir
				)
			. $delim;
}

1;

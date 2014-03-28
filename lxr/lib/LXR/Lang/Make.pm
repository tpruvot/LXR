# -*- tab-width: 4 -*-
###############################################
#
# $Id: Make.pm,v 1.4 2013/11/08 09:06:26 ajlittoz Exp $
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

=head1 Make language module

This module is the Make language highlighting engine.
It is driven by specifications read from file I<generic.conf>.

=cut

package LXR::Lang::Make;

$CVSID = '$Id: Make.pm,v 1.4 2013/11/08 09:06:26 ajlittoz Exp $ ';

use strict;
require LXR::Lang::Generic;

our @ISA = ('LXR::Lang::Generic');



=head2 C<processinclude ($frag, $dir)>

Method C<processinclude> is invoked to process a Make I<include> directive.

=over

=item 1 C<$frag>

a I<reference to a string> containing the directive

=item 1 C<$dir>

an optional I<string> containing a preferred directory for the include'd file

=back

Make C<include> may request several files.
It is thus necessary to iterate on the list.

=cut

sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $file;		# language include file
	my $path;		# OS include file
	my $target = '[s-]?include\s+';	# directive pattern

	$$frag = '';
	while (1) {
		if ($source !~ s/^		# reminder: no initial space in the grammar
						(${target})	# reserved keyword for include construct
						(\S+)	# file name
						//sx) {
			# Guard against syntax error or variant
			# Advance past keyword, so that parsing may continue without loop.
			$source =~ s/^(\S+)//;	# Erase keyword
			if (length($1) > 0) {
				$$frag .= "<span class='reserved'>$1</span>";
			}
			&LXR::SimpleParse::requeuefrag($source);
			return;
		}

		# First iteration is for 'include' keyword.
		# Following are only for whitespace separators.
		$target = '\s+';

		$file    = $2;
		$path    = $file;
		$$frag .= 	"<span class='reserved'>$1</span>";

		# Check start of comment
		if ('#' eq substr($file, 0, 1)) {
			&LXR::SimpleParse::requeuefrag($file.$source);
			return;
		}

		# Create the hyperlink
		$$frag .= $self->_linkincludedirs
					( &LXR::Common::incref
						($file, 'include', $path, $dir)
					, $file
					, '/'
					, $path
					, $dir
					);
	}
}

1;

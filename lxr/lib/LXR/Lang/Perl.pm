# -*- tab-width: 4 -*-
###############################################
#
# $Id: Perl.pm,v 1.14 2013/09/21 12:54:53 ajlittoz Exp $
#
# Enhances the support for the Perl language over that provided by
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
#
###############################################

=head1 Perl language module

This module is the Perl language highlighting engine.

It shares most of its methods with I<Generic.pm>.
It only overrides C<processinclude> for efficiency.

=cut

package LXR::Lang::Perl;

$CVSID = '$Id: Perl.pm,v 1.14 2013/09/21 12:54:53 ajlittoz Exp $ ';

use strict;
use LXR::Common;
use LXR::Lang;
require LXR::Lang::Generic;

our @ISA = ('LXR::Lang::Generic');


=head2 C<processinclude ($frag, $dir)>

Method C<processinclude> is invoked to process a Perl I<include> directive.

=over

=item 1 C<$frag>

a I<string> containing the directive

=item 1 C<$dir>

an optional I<string> containing a preferred directory for the include'd file

=back

This method does not reference the configuration file.
However, the different reg-exps are still maintained there
as check case for the generic parser.

=cut

sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# include directive name and spacing
	my $file;		# language include file
	my $path;		# OS include file
	my $link;		# link to include file

	# Faster surrogate for 'directive'
	if ($source =~ s/^		# reminder: no initial space in the grammar
					([\w]+	# reserved keyword for include construct
					\s+)	#   and space is same capture
					([\w:]+)# bareword
					//sx) {
	### Bareword syntax: lib::module notation must be converted
	#	to file path lib/module.pm
		$dirname = $1;
		$file    = $2;
		$path    = $file;

		# Faster surrogates for 'global' and 'last'
		$path =~ s@::@/@g;		# Replace Perl delimiters
		$path =~ s@$@.pm@;		# Add file extension

		# Create the hyperlinks
		$link = $self->_linkincludedirs
					( &LXR::Common::incref
						($file, 'include', $path, $dir)
					, $file
					, '::'
					, $path
					, $dir
					);
	} elsif ($source =~ s/^	# reminder: no initial space in the grammar
					([\w]+	# reserved keyword for include construct
					\s+)	#   and space in same capture
					(["'])	# opening string delimiter
					(.+)	# string
					\g{-2}	# matching closing delimiter (5.10 syntax!)
					//sx) {
	### String syntax: string is file path
	#	NOTE: the string may coontain escaped delimiters which are
	#			not handled by the above pattern.
		$dirname = $1;
		my $delim= $2;
		$file    = $3;
		$path    = $file;

		# Create the hyperlinks
		$link = $self->_linkincludedirs
					( &LXR::Common::incref
						($file, 'include', $path, $dir)
					, $file
					, '/'
					, $path
					, $dir
					);
		$link = $delim . $link . $delim;
	} else {
		# Guard against syntax error or variant
		# Advance past keyword, so that parsing may continue without loop.
		$source =~ s/^([\w]+)//;	# Erase keyword
		$dirname = $1;
		$link = '';
	}

	# As a goodie, rescan the tail of use/require for Perl code
	&LXR::SimpleParse::requeuefrag($source);

	# Assemble the highlighted bits
	$$frag =	"<span class='reserved'>$dirname</span>"
			.	$link;
}

1;

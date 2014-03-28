# -*- tab-width: 4 -*-
###############################################
#
# $Id: Pascal.pm,v 1.5 2013/11/08 09:04:27 ajlittoz Exp $
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

=head1 Pascal language module

This module is the Pascal language highlighting engine.
It is driven by specifications read from file I<generic.conf>.

=cut

package LXR::Lang::Pascal;

$CVSID = '$Id: Pascal.pm,v 1.5 2013/11/08 09:04:27 ajlittoz Exp $ ';

use strict;
use LXR::Lang;
require LXR::Lang::Generic;

our @ISA = ('LXR::Lang::Generic');


=head2 C<new ($pathname, $releaseid, $lang)>

Method C<new> creates a new language object.

=over

=item 1 C<$pathname>

a I<string> containing the name of the file to parse

=item 1 C<$releaseid>

a I<string> containing the release (version) of the file to parse

=item 1 C<$lang>

a I<string> which is the I<key> for the specification I<hash>
C<'langmap'> in file I<generic.conf>

=back

This method is the specific constructor for Pascal source files.

The real construction is done by I<Generic>'s C<new> method.

A specific constructor is needed to capture the file extension
which varies from platform to platform.
This extension is needed to synthesize included file names.

=cut

sub new {
	my ($proto, $pathname, $releaseid, $lang) = @_;
	my $class = ref($proto) || $proto;

	# Call the effective creator
	my $self = $class->SUPER::new($pathname, $releaseid, $lang);
	$pathname =~ m/\.([^.]+)$/;
	$$self{'pasextension'}  = $1;
	return $self;
}


=head2 C<processinclude ($frag, $dir)>

Method C<processinclude> is invoked to process a Pascal I<include> directive.

=over

=item 1 C<$frag>

a I<reference to a string> containing the directive

=item 1 C<$dir>

an optional I<string> containing a preferred directory for the include'd file

=back

Pascal C<uses> may request several files through a comma-separated list.
It is thus necessary to iterate on the list.

=cut

sub processinclude {
	my ($self, $frag, $dir) = @_;

	my $source = $$frag;
	my $dirname;	# uses directive name and spacing
	my $dictname;
	my $file;		# language include file
	my $path;		# OS include file
	my $link;		# link to include file
	my $extens = $$self{'pasextension'};
	my $target = 'uses\s+';	# directive pattern

	$$frag = '';
	while (1) {
		if ($source !~ s/^		# reminder: no initial space in the grammar
						(${target})	# reserved keyword for include construct
						(\w+)	# Pascal module
						//sx) {
			# Guard against syntax error or variant
			# Advance past keyword, so that parsing may continue without loop.
			$source =~ s/^(\s*\S+)//;	# Erase keyword
			$dirname = $1;
			$$frag = "<span class='reserved'>$dirname</span>";
			&LXR::SimpleParse::requeuefrag($source);
			return;
		}

		# First iteration is for 'uses' keyword.
		# Following are only for the comma separator
		$target = '\s*,\s*';

		$dirname = $1;
		$file    = $2;
		$path    = $file;
		($dictname = $dirname) =~ s/\s//g;
		$$frag .= 	( $self->isreserved(uc($dictname))
					? "<span class='reserved'>$dirname</span>"
					: $dirname
					);	

		$path =~ s@$@.${extens}@;		# Add file extension

		# Create the hyperlink
		$link = &LXR::Common::incref($file, 'include', $path, $dir);
		if (!defined($link)) {
			$link = $file;
		}
		$$frag .= $link;
		if ($source =~ m/^\s*;$/) {	# End of directive?
			$$frag .= $source;
			return;
		}
	}
}

1;

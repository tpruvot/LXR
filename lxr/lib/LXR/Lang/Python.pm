# -*- tab-width: 4 -*-
###############################################
#
# $Id: Python.pm,v 1.11 2013/09/24 07:59:19 ajlittoz Exp $
#
# Enhances the support for the Python language over that provided by
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

This module is the Python language highlighting engine.

It shares most of its methods with I<Generic.pm>.
It only overrides C<processinclude> for efficiency.

=cut

package LXR::Lang::Python;

$CVSID = '$Id: Python.pm,v 1.11 2013/09/24 07:59:19 ajlittoz Exp $ ';

use strict;
use LXR::Common;
use LXR::Lang;
require LXR::Lang::Generic;

our @ISA = ('LXR::Lang::Generic');


=head2 C<processinclude ($frag, $dir)>

Method C<processinclude> is invoked to process a Python I<include> directive.

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
	my $dirname;	# include directive name
	my $file;		# language include file
	my $path;		# OS include file
	my $link;		# link to include file

	# Faster surrogate for 'directive'
	if ($source !~ s/^		# reminder: no initial space in the grammar
					([\w]+	# reserved keyword for include construct
					\s+)	# and space
					([\w.]+)
					//sx) {
		# Variant that we can't (or don't want to) handle, such as
		# from xxx import (a, b, c)
		# Advance past keyword, so that parsing may continue without loop.
		$source =~ s/^([\w]+)//;	# Erase keyword
		$dirname = $1;
		$$frag = "<span class='reserved'>$dirname</span>";
		&LXR::SimpleParse::requeuefrag($source);
		return;
	}

	$dirname = $1;
	$file    = $2;
	$path    = $file;

	# Faster surrogates 'last'
	$path =~ s@\.@/@g;		# Replace Python delimiters
	$path =~ s@$@.py@;		# Add file extension

	# Create the hyperlinks
	$link = &LXR::Common::incref($file, 'include', $path, $dir);
	if (!defined($link)) {
		# Can it be a directory ('from ... import ...' instruction ?)
		# NOTE: the parser is too rudimentary to cope with a directory
		#		after the import keyword since it has lost any knowledge
		#		of the possible from sentence. It cannot resolve the
		#		name (or directory) context needed for import.
		# NOTE: we could also link to __init__.py in the directory but
		#		this would suppress the possibility to click-link to
		#		the directory itself.
		$path =~ s@\.py$@@;	# Remove file extension
		$link = &LXR::Lang::incdirref($file, 'include', $path, $dir);
		# Erase last path separator from <a> link to enable
		# following partial path processing.
		# NOTE: this creates a dependency of link structure from incref!
		if (substr($link, 0, 1) eq '<') {
			$link =~ s!/">!">!;
		}
	}
	$link = $self->_linkincludedirs
				( $link
				, $file
				, '.'
				, $path
				, $dir
				);
	if (substr($link, 0, 1) ne '<') {
		$link = join	( '.'
						, map {$self->processcode(\$_)}
							split(/\./, $link)
						);
	}

	# As a goodie, rescan the tail of import/from for Python code
	&LXR::SimpleParse::requeuefrag($source);

	# Assemble the highlighted bits
	$$frag =	"<span class='reserved'>$dirname</span>"
			.	$link;
}

1;

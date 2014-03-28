# -*- tab-width: 4 -*-
###############################################
#
# $Id: Cobol.pm,v 1.6 2013/11/08 09:04:27 ajlittoz Exp $
#
# Enhances the support for the Cobol language over that provided by
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

package LXR::Lang::Cobol;

my $CVSID = '$Id: Cobol.pm,v 1.6 2013/11/08 09:04:27 ajlittoz Exp $ ';

use strict;
use LXR::Common;
require LXR::Lang;
require LXR::Lang::Generic;

@LXR::Lang::Cobol::ISA = ('LXR::Lang::Generic');

# TODO: Cobol.pm is probably buggy and deserves a thorough examination
#		ajl - 2012-09-17

sub referencefile { }

sub processcode {
	my ($self, $code) = @_;

	$$code =~ s {(^|[^\w\#-])([\w~-][\w-]*)\b}
	{
	  $1.
		( $2 eq ''
		? $2
		:	( $self->isreserved(uc($2))
			? "<span class='reserved'>$2</span>"
			:	( $index->issymbol(uc($2), $$self{'releaseid'})
				? join($2, @{$$self{'itag'}})
				:  $2
			)
		);
	}ge;

}

1;


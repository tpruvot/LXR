# -*- tab-width: 4 -*-
###############################################
#
# $Id: LXRversion.pm,v 1.3 2012/03/29 13:43:19 ajlittoz Exp $

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

# Define LXR public version

# NOTE to developers:
#
#	This package is now a template which is adjusted by script
#	makerelease.pl during release procedure.
#	It was too easy (and too frequent) to forget to set it to
#	the correct value.

# NOTE to end users:
#	Change manually the below value when you make modifications to
#	LXR so that there results no confusion between the general version
#	and your custom version.

package LXRversion;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw($LXRversion);

#our $LXRversion = "%LXRRELEASENUMBER%";

our $LXRversion = "0.12-git";

1;

# Define LXR public version
#
# NOTE to developers:
#
#	Remember to update this variable when releasing
#	a new version.
#
# Any version numbering scheme is accepted. Apply
# the agreed policy (if any).

package LXRversion;

use strict;
use warnings;

require Exporter;

our @ISA = qw(Exporter);
our @EXPORT = qw($LXRversion);

our $LXRversion = "0.10";

1;

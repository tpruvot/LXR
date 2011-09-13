# -*- tab-width: 4 -*- ###############################################
#
# $Id: SimpleParse.pm,v 1.18 2011/03/17 10:29:04 ajlittoz Exp $

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

package LXR::SimpleParse;

$CVSID = '$Id: SimpleParse.pm,v 1.18 2011/03/17 10:29:04 ajlittoz Exp $ ';

use strict;
use integer;

require Exporter;

use vars qw(@ISA @EXPORT);

@ISA    = qw(Exporter);
@EXPORT = qw(&doparse &untabify &init &nextfrag);

my $fileh;       # File handle
my @frags;       # Fragments in queue
my @bodyid;      # Array of body type ids
my @open;        # Fragment opening delimiters
my @term;        # Fragment closing delimiters
my @stay;        # Fragment maintaining current context
my $split;       # Fragmentation regexp
my $open;        # Fragment opening regexp
my $continue;	 # Fragment maintaining current context for "no category"
my $tabwidth;    # Tab width

sub init {
	my @blksep;

	$fileh    = "";
	@frags    = ();
	@bodyid   = ();
	@open     = ();
	@term     = ();
	@stay     = ();
	$split    = "";
	$open     = "";
	$continue = "";
	$tabwidth = 8;
	my $tabhint;

	($fileh, $tabhint, @blksep) = @_;
	$tabwidth = $tabhint || $tabwidth;

	foreach my $s (@blksep) {
		my $k = (keys(%$s))[0];
		if ($k eq "atom") {		# special case for uncategorised fragments
			$continue = $$s{$k};
		}
		else {
			my $v = @$s{$k};
			push (@bodyid, $k);
			push (@open, $$v[0]);
			if (defined($$v[1]))
					{ push (@term, $$v[1]); }
			else	{ push (@term, undef); }
			if (defined($$v[2]))
					{ push (@stay, $$v[2]); }
			else	{ push (@stay, ''); }
		}
	}

	foreach (@open) {
		$open  .= "^($_)\$|";
		$split .= "$_|";
	}
	chop($open);
	chop($split);
}

sub untabify {
	my $t = $_[1] || 8;

	$_[0] =~ s/^(\t+)/(' ' x ($t * length($1)))/ge;                 # Optimize for common case.
	$_[0] =~ s/([^\t]*)\t/$1.(' ' x ($t - (length($1) % $t)))/ge;
	return ($_[0]);
}

sub nextfrag {
	my $btype = undef;
	my $frag  = undef;
	my $term  = undef;
	my $stay  = $continue;
	my $line  = '';

# 		print "nextfrag called\n";

	while (1) {

		# read one more line if we have processed
		# all of the previously read line
		if ($#frags < 0) {
			$line = $fileh->getline;

			if (   $. <= 2
				&& $line =~ /^.*-[*]-.*?[ \t;]tab-width:[ \t]*([0-9]+).*-[*]-/)
			{
				# make sure there really is a non-zero tabwidth
				if ($1) { $tabwidth = $1; }
			}

				#			&untabify($line, $tabwidth); # We inline this for performance.
				# Optimize for common case.
			if (defined($line)) {
				$line =~ s/^(\t+)/' ' x ($tabwidth * length($1))/ge;
				$line =~ s/([^\t]*)\t/$1.(' ' x ($tabwidth - (length($1) % $tabwidth)))/ge;

				$frags[0] = $line;
			}
		}

		last if $#frags < 0;

		# skip empty fragments
		if ($frags[0] eq '') {
			shift(@frags);
		}

		# check for "stay" atoms
		my $next = shift(@frags);
		if ($stay ne '') {
			while ($next =~ /$stay/) {
		# Make sure $stay occurs BEFORE $split if no $term
		#	else $stay before $term
				$next =~ /^(.*?)($stay)/s;
				my $spos = undef;
				if (defined($2)) {
					$spos = length($1) || 0;
				}
				my $opos = undef;
				my $change = $term || $split;
				if ($next =~ /$change/) {
					$next =~ /^(.*?)($change)/s;
					if (defined($2)) {
						$opos = length($1) || 0 ;
					}
				}
				last if (defined($opos) && ($spos > $opos));
		# There definitely is a "stay" atom, shift it into fragment
				$next =~ s/^(.*?)($stay)//s;
#				$frag = "" unless defined($frag);
				$frag .= $1 . $2;
			}
		}

		# check if we are inside a fragment
		if (defined($frag)) {
			if (defined($btype)) {
				if ($next =~ /$term/) {			# A close delim in this fragment?
					$next =~ /^(.*?)($term)(.*)/s;
					if ($3 ne '') {
						unshift(@frags, $3);	# Requeue last part
					}
					$frag .= $1 . $2;
					last;						# We are done, terminator met
				}

				# Add to the fragment
				$frag .= $next;

			}
			else {
				if ($next =~ /^($split)/) {
					unshift(@frags, $next);	# requeue block
					#					print "encountered open token while btype was $btype\n";
					last;
				}
				if ($next =~ /$split/) {		# An open delim in this fragment?
					$next =~ /^(.*?)($split)(.*)/s;
					if ($3 ne '') {
						unshift(@frags, $3);	# Requeue last part
					}
					unshift(@frags, $2);		# Requeue open delimiter
					$next = $1
				}
				$frag .= $next;
			}
		}

		else {
					#	print "start of new fragment\n";
			# Find the blocktype of the current block
			if ($next =~ /$split/) {			# An open delim in this fragment?
				$next =~ /^(.*?)($split)(.*)/s;	# Split fragment at first
				if ($3 ne '') {
					unshift(@frags, $3);		# Requeue last part
				}
				if ($1 ne '') {					# Choose which frag to process
					unshift(@frags, $2);		# Queue delimiter
					$frag = $1;
				}
				else {
					$frag = $2;
				}
			}
			else {								# Full fragment (no delim)
				$frag = $next;
			}
			if (defined($frag) && (@_ = $frag =~ /$open/)) {
						#		print "hit:$frag\n";
				# grep in a scalar context returns the number of times
				# EXPR evaluates to true, which is this case will be
				# the index of the first defined element in @_.

				my $i = 1;
				$btype = grep { $i &&= !defined($_) } @_;
				if (!defined($term[$btype])) {
					print "fragment without terminator\n";
					last;
				}
				else {
					$term = $term[$btype];
					$stay = $stay[$btype];
				}
			}
		}
	}
	$btype = $bodyid[$btype] if defined($btype);

	return ($btype, $frag);
}

1;

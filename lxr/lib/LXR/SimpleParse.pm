# -*- tab-width: 4 -*- #
##############################################
#
# $Id: SimpleParse.pm,v 1.23 2013/11/08 08:27:24 ajlittoz Exp $
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
##############################################

=head1 SimpleParse module

This module is the elementary parser in charge of splitting the
source file into homogeneous regions (i.e. fragments defined by
'spec's in generic.conf).

=cut

package LXR::SimpleParse;

$CVSID = '$Id: SimpleParse.pm,v 1.23 2013/11/08 08:27:24 ajlittoz Exp $ ';

use strict;
use integer;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(
	&doparse
	&untabify
	&init
	&nextfrag
	$dountab
);

# Global module variables

my $fileh;		# File handle
my @frags;		# Fragments in queue
my $next;		# Current fragment
my @bodyid;		# Array of body type ids
my @open;		# Fragment opening delimiters
my @term;		# Fragment closing delimiters
my @stay;		# Fragment maintaining current context
my $split;		# Fragmentation regexp
my $open;		# Fragment opening regexp
my $continue;	# Fragment maintaining current context for "no category"
my $tabwidth;   # Tab width
our $dountab;	# Untabify flag (in nextfrag)


=head2 C<init ($fileh, $tabhint, @blksep)>

C<init> initializes the global variables
and builds the detection regexps.

=over

=item 1 C<$fileh>

a I<filehandle> for the source file

=item 1 C<$tabhint>

hint for the tab width (defaults to 8 if not defined)

Actual value can be given in an emacs-style comment as the first
line of the file.

=item 1 C<@blksep>

an I<array> of references to I<hashes> defining the different
categories for this languages (see C<generic.conf>)

=back

=cut

sub init {
	my @blksep;

	@frags    = ();
	$next     = undef;
	@bodyid   = ();
	@open     = ();
	@term     = ();
	@stay     = ();
	$split    = '';
	$open     = '';
	$continue = undef;
	$dountab  = 1;
	my $tabhint;

	($fileh, $tabhint, @blksep) = @_;
	$tabwidth = $tabhint // 8;

# Consider every specification in the order given
	foreach my $s (@blksep) {
		#	$k is category name (e.g; comment, string, ...)
		my $k = (keys(%$s))[0];
		if ($k eq 'atom') {		# special case for uncategorised fragments
			$continue = $$s{$k};
		} else {
			#	Value is itself a reference to an array
			my $v = $$s{$k};
			push (@bodyid, $k);			# Category name
			push (@open, $$v[0]);		# Open delimiter
			push (@term, $$v[1]);	# Closing delimiter
			push (@stay, $$v[2]);	# Locking pattern
		}
	}

	# Create the regexps to find any opening delimiter
	foreach (@open) {
		$open  .= "($_)|";
		$split .= "$_|";
	}
	chop($open);	# Remove the last (extraneous) bar
	$open = '^[\xFF\n]*(?:'.$open.')$';	# Set the anchors
	chop($split);	# Remove the last (extraneous) bar
}


=head2 C<untabify ($line, $tab)>

C<untabify> replaces TAB characters by spaces.

=over

=item 1 C<$line>

I<string> to untabify

=item 1 C<$tab>

number of spaces for a TAB (defaults to 8 if not defined)

=back

Returns the line after replacement.

Note that this sub is presently only used by sub C<markupfile>
when no specific parser definition could be found.
No attempt is made to interpret an emacs-style tab specification.
Consequently, tab width can be erroneous.

=cut

sub untabify {
	my $t = $_[1] || 8;

	$_[0] =~ s/^(\t+)/(' ' x ($t * length($1)))/geo;	# Optimize for common case.
	$_[0] =~ s/([^\t]*)\t/$1.(' ' x ($t - (length($1) % $t)))/geo;
	return ($_[0]);
}


=head2 C<nextfrag ()>

C<nextfrag> returns the next categorized region of the source file.

Returned value is a list: C<($btype, $frag)>.

=over

=item 1 C<$btype>

a I<string> giving the category name

=item 1 C<$frag>

a I<string> containing the region

Note thet the "region" may span several lines.

=back

C<nextfrag> implements the LXR parser. It is critical for global
performance. Unhappily, two factors put a heavy penalty on it:

1- Perl is an interpreted language,

2- parsing with regexp is not as efficient as a finite state 
automaton (FSA).

=over

=item

I<Speed is acceptable when displaying a file (since time here is
dominated by HTML editing).>

=item

I<Raw speed can be seen during C<genxref> where the full tree is
parsed. It could be worth to replace the parser by a compiled
deterministic FSA version.>

=back

=cut

sub nextfrag {
	my $btype = undef;	# index of category, then name on return
	my $frag  = undef;	# output buffer
	my $term  = undef;	# closing delim pattern
	my $stay  = $continue;	# lock pattern
	my $change = $split;	# delimiter introducing a category change
	# These initial values set the state for the "anonymous"
	# default category (i.e. code). It is switched to another
	# state if $next (the following characters to process)
	# begins with a starting delimiter.
	my $line;			# line buffer
	my $opos;			# position of this delimiter
	my $spos;			# position of a (conflicting?) "stay" delimimter

# 		print "nextfrag called\n";

	while (1) {
		$next = shift(@frags) if !defined($next);

		# read one more line if we have processed
		# all of the previously read line
		if (!$next) {
			$line = $fileh->getline;
		#	Exit loop on EOF returning the currently assembled region
		#	or an undefined pair
			last if !defined($line);
			# Interpret an Emacs-style tab specification
			if	(  $. <= 2		# Line # 1 or 2?
				&& $line =~ m/^.*-\*-.*?[ \t;]tab-width:[ \t]*([0-9]+).*-\*-/o
				) {
				if ($1) {	# make sure there really is a non-zero tabwidth
					$tabwidth = $1;
				}
			}
#			&untabify($line, $tabwidth); # We inline this for performance.
			# Optimize for common case.
			if ($dountab) {
				$line =~ s/^(\t+)/' ' x ($tabwidth * length($1))/geo;
				$line =~ s/([^\t]*)\t/$1.(' ' x ($tabwidth - (length($1) % $tabwidth)))/geo;
			}
			$next = "\xFF" . $line;	# Add SOL marker
		}

#	If the specification defines a locking pattern (in $stay),
#	we must be very careful: locking the current state is legal
#	only if the "stay" atom is located inside the present category.
#	The test below is rather complicated because we rely on
#	pattern matching, not LR parsing.
#	1-	See if there is a terminator (either the closing delimiter
#		if defined or any opening delimiter) in the line.
#		If none, the whole line is made of a single category.
#		Otherwise, note its position.
#	2-	Loop on the presence of a "stay" atom in the line.
#		If none, leave the loop.
#	3-	If the "stay" atom is located after (i.e. at the right of)
#		the closing delimiter, leave the loop.
#	4-	The part up to and including the "stay" atom is shifted
#		into the candidate fragment and the position of the
#		terminator is updated for the next iteration of the
#		inner loop.
#	The process is repeated until there is no more "stay" atoms
#	in the correct range.

		# check for "stay" atoms
		if (defined($stay)) {
			# Look for "term" or any "open delim" if not defined
			$opos = undef;
			while	(	!defined($opos)
					&&	$next =~ m/$change/
					) {
			# Compute the position of the "end" delimiter
				$opos = $-[0];
				while ($next =~ m/$stay/) {
				# Compute the end position of the "stay" atom
					$spos = $+[0];
				# Compare positions and make decision
					last if $-[0] > $opos;
				# There is a "stay" atom, shift it into fragment
					$frag .= substr($next, 0, $spos);
					$next = substr($next, $spos);
					$opos -= $spos;
					if ($opos <= 0) {
						$opos = undef;
						last;
					}
				}
			}
		}

#	Have we already started a region?
		if	(	defined($frag)				# something in output buffer?
			&&	$frag !~ m/^[\xFF\n]*$/o	# not just newlines?
			) {
#	We already have something in the buffer.
#	Is it a named category?
#	Add to output buffer till we find a closing delimiter.
#	Remember that "stay" constructs have been processed above.
			if (defined($btype) && defined($term)) {
				if ($next =~ m/$term/) {	# A close delim in this fragment?
					$frag .= substr($next, 0, $+[0]);
					$next = substr($next, $+[0]);
					last;					# We are done, terminator met
				}
#	An anonymous region is in the buffer (it defaults to "code").
#	This default region is left on any opening delimiter.
			} else {
					# Split at delimiter
				if ($next =~ s/^(.*?)($split)//) {	# An open delim in this fragment?
					unshift(@frags, $next) if $next ne '';	# Requeue last part
					$frag .= $1;		# Stuff part before delim
					$next = $2;			# Delimiter
					last;
				}
			}
			$frag .= $next;				# Full fragment (no delim)
			$next = undef;
		} else {
#	This begins a new region (output buffer empty).
#	Stuff the sequence up to any opening delimiter or the complete
#	input line if there is no delimiter in range.
# 			print "start of new fragment\n";
			if ($next =~ s/^(.*?)($split)//) {	# An open delim in this fragment?
				if ($1 ne '') {			# Anything before the delim?
					unshift(@frags, $next) if $next ne '';	# Requeue last part
					$next = $2;			# Delimiter
					$frag .= $1;		# Stuff part before delim
					last if $frag !~ m/^[\xFF\n]*$/o;
					$frag .= $next;		# Fragment was "empty"
					$next = undef;
				} else {
					$frag .= $2;
					$next = undef if $next eq '';
				}
			} else {					# Full fragment (no delim)
				$frag .= $next;
				$next = undef;
			}
#	Find the blocktype of the current block
# 			if (defined($frag) && (@_ = $frag =~ m/$open/)) {
			if (@_ = $frag =~ m/$open/) {
# 				print "hit:$frag\n";
				# grep in a scalar context returns the number of times
				# EXPR evaluates to true, which is this case will be
				# the index of the first defined element in @_.

				my $i = 1;
				$btype = grep { $i &&= !defined($_) } @_;
				if (!defined($term[$btype])) {
#					print "fragment without terminator\n";
					last;
				} else {
#	Set the category characteristics for further parsing
					$term	= $term[$btype];
					if ('CODE' eq ref($term)) {
						$term = eval(&$term());
					}
					$stay	= $stay[$btype];
					$change	= $term // $split;
 				}
			}
		}
	}
	$btype = $bodyid[$btype] if defined($btype);
	$frag =~ s/\xFF//go;	# Remove start of line markers
	return ($btype, $frag);
}


=head2 C<requeuefrag ($frag)>

C<requeuefrag> stores a string in the source input buffer for
scanning by the next call to C<nextfrag>.

=over

=item 1 C<$frag>

I<string> to scan next

=back

This sub is useful for rescanning a (tail) part of a fragment when
it is discovered it contains a different category or to force
parsing of a generated string.

B<Caveat:>

=over

=item

When using this sub, pay special attention to the order of
requests so that you do not create permutations of source
sequences: it is a stack (LIFO)!

=back

=cut

sub requeuefrag {
	unshift(@frags, $next) if defined($next);	# Requeue fragment
	$next = $_[0];
}

1;

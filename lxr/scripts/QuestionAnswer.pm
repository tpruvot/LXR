# -*- tab-width: 4 -*-
###############################################
#
# $Id: QuestionAnswer.pm,v 1.4 2013/11/07 16:35:52 ajlittoz Exp $
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

# $Id: QuestionAnswer.pm,v 1.4 2013/11/07 16:35:52 ajlittoz Exp $

package QuestionAnswer;

use strict;
use VTescape;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	get_user_choice
);

#	find_unique_prefix:
#	a sub to compute the unique prefixes for each element of a list
#	Returns a list of patterns matching the elements: a matching
#	string may have any length from unique prefix up to complete
#	string.
sub find_unique_prefix {
	my ($list) = @_;
	my @pats;

	my $flat = '#' . join('#', @$list);
PAT:
	foreach my $pat (@$list) {
		my $pfix = "#";
		my @chars = split(//, $pat);
		while (my $c = shift(@chars)) {
			$pfix .= $c;
			if (1 == (@_ = $flat =~ m/$pfix/ig)) {
				my $sl = @chars;	#suffix length
				$pfix .= '('x($sl>0) . join('(', @chars) . ')?'x$sl;
				push(@pats, '^' . substr($pfix, 1));
				next PAT;
			}
		}
		print "${VTred}FATAL:${VTnorm} no unique prefix for $pat!\n";
		exit 2;
	}
	return @pats;
}

#	get_user_choice:
#	a sub to choose an answer among possible choices
#	- $question: question to display
#	- $default: default answer if empty user entry
#		-3, open question, empty answer allowed
#		-2, open question, no default answer, empty not allowed
#		-1, open question with default answer
#		 0, closed question, no default answer
#		>0, closed question, default answer number (first is 1)
#	- $choices: ref to array of choice strings or optional validation
#		pairs for dft < 0
#	- $answers: ref to normalised answers
#	$choices and $answers must have same number of strings for dft >= 0.
#	Both may be omitted if $default < 0.
sub get_user_choice {
	my ($question, $default, $choices, $answers) = @_;
	my @pats;
	my @choices;
	my @opendefault;

	#	Build the patterns associated with answers
	if ($default-- >= 0) {
		if	(  !defined($choices)
			|| !defined($answers)
			|| @$choices != @$answers
			) {
		print "${VTred}FATAL:${VTnorm} incorrect choices and/or answers for \"$question\"!\n";
		exit 2;
		}
		if ($default >= @$choices) {
		print "${VTred}FATAL:${VTnorm} invalid default choice for \"$question\"!\n";
		exit 2;
		}
		@pats = find_unique_prefix ($choices);
		@choices = map(lc, @$choices);
	#	Uppercase default answer
		$choices[$default] = $VTgreen . uc($$choices[$default]);
	}

	#	Check open-with-default case
	if ($default == -2) {
		if (defined($answers)) {
			@choices[0] = $VTgreen . $$answers[0];
		} else {
			print "${VTred}FATAL:${VTnorm} no default choice for \"$question\"!\n";
			exit 2;
		}
	}

	#	Get answer from user and return a normalised one
QLOOP:
	while (1) {
		print $question;
		if (@choices) {
			print " [${VTyellow}", join("${VTnorm}/${VTyellow}", @choices), "${VTnorm}]";
		}
		print " ${VTslow}${VTyellow}>${VTnorm} ";
		my $userentry = <STDIN>;
		chomp($userentry);
		#	See if user just hit "return"; if this is valid, give
		#	default answer, otherwise ask again.
		if ($userentry eq '') {
			if ($default >= 0) {
				return $$answers[$default];
			} elsif ($default == -2) {
				return $$answers[0];
			} elsif ($default == -4) {
				return '';
			}
			print "No default choice, try again...\n";
			next;
		}
		#	If open question, return free text
		if ($default < -1) {
			if (defined($choices)) {	# Any constraint check?
				my ($chk, $msg, $i);
				for ($i = 0; $i < $#$choices; $i++) {
					$chk = $$choices[$i];
					$msg = $$choices[++$i];
					if ($userentry !~ m/$chk/) {
						print "${VTred}ERROR:${VTnorm} $msg, try again ...\n";
						next QLOOP;
					}
				}
			}
			return $userentry;
		}
		#	Closed question: find which choice
		for (my $i=0; $i<@pats; $i++) {
			my $pat = $pats[$i];
			return $$answers[$i] if $userentry =~ m/$pat/i;
		}
		print "${VTred}ERROR:${VTnorm} invalid answer, try again ...\n";
	}
}

1;

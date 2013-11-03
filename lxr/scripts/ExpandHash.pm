#!/usr/bin/perl
# -*- tab-width: 4 -*-
###############################################
#
# $Id: ExpandHash.pm,v 1.1 2012/09/22 08:50:33 ajlittoz Exp $
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

# $Id: ExpandHash.pm,v 1.1 2012/09/22 08:50:33 ajlittoz Exp $

package ExpandHash;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	expand_hash
);

use strict;
use File::Path;
use lib do { $0 =~ m{(.*)/}; "$1" };
use QuestionAnswer;
use VTescape;

##############################################################
#
#	Expand a file with Perl or bash style comments
#
##############################################################

# expand_hash takes 2 file arguments, $source and $dest.
# $source is the "model" file where special comments drive text copy
# and expansion to the $dest file.
# Positions in the files must already have been set to the adequate
# locations for 1) start of interpretation in $source and 2) start
# of write in $dest.
# Files are not closed at end of interpretation to allow for extra
# additions in the calling program.

# The other arguments provide ancillary data to the interpreter.

# *** Source file ***

# == Marker substitution ==
# Text lines may contain %abcd% 'markers' requesting replacement
# by the value of an element of hash referenced by $markers, i.e. value
# of $$markers{'%abcd%'}.

# == Erasable comments ==
# Comments starting with #- are not copied to $dest.

# == Commands ==
# All interpreted commands appear as #@ comments in column 1.
# The command is defined by an uppercase letter following #@:

# = Print message: #@V text =
# If $verbose is true, print text of comment on STDOUT

# = Ask a question:            #@Q  question; kind; choices; answers
# = Ask a question repeatedly: #@QR question; kind; choices; answers
# kind defines the expected answer:
#  -2 any but empty string is not allowed
#  -1 any, empty string implies default answer
#   0 one among choices, empty string not allowed
# i>0 one among choices, empty string means choice number i
# choices is empty for -2 and -1
# answers provides "normalised" answers corresponding to choices.
#  If kind=-1, must define a default answer (possibly empty).
# choices and answers are comma-separated lists.
# Answer to question is stored for use in #@A.
# Flag R in #@QR changes #@A behaviour.

# = Use an answer: #@A text =
# Sustitute @A in text with answer to preceding question and emit text.
# If question was #@QR, ask again and process #@A until empty answer.

# = Define marker: #@D marker=option =
# Define a %marker% (% characters are internally added) equal to the
# value of an option. Afterwards, %marker% can be used for substitution.
# NOTE:	since the simple parser only allows for A-Za-z0-9_ characters
#		in both marker and option, a translation is needed between the
#		shell option name and the #@D option name.
#		This is done through the hash reference $option_trans, i.e.
#		$$option_trans{'option'} gives the value to use.

# == Conditional blocks ==
# Conditional blocks extend from a #@begin_x line to a #@end_x line,
# where x is an uppercase letter. x must be the same for the sentinels
# to match.
# Conditional blocks may be nested.

# = Conditional on marker existence: #@begin_M  marker =
# = Negated condition:               #@begin_M !marker =
# The following lines are kept if marker %marker% (% characters are
# internally added) exists, skipped otherwise.
# The test is reversed for the negated condition.

# = Conditional on option existence: #@begin_O  option =
# = Negated condition:               #@begin_O !option =
# The following lines are kept if option has been given on shell command
# line, skipped otherwise. The test is reversed for the negated condition.
# This uses the $option_trans hash reference
# NOTE:	--noone tells nothing about --one here (one and noone are
#		considered as 2 different options).

# = Conditional on option value: #@begin_O option==value =
# = Not equal condition        : #@begin_O option!=value =
# The following lines are kept if option is equal to value on shell command
# line, skipped otherwise. The test is reversed for the not equal condition.
# This uses the $option_trans hash reference
# It is intended for --context=m type of option.

# = Interactive conditional: #@begin_Y question;1;yes,no;Y,N =
# = Negated condition:       #@begin_N question;2;yes,no;Y,N =
# If answer to question is Y (or N), the following lines are kept,
# skipped otherwise.
# NOTE: the Y or N answers must be uppercase.

#	Shared variables
my $qtext;
my $qdeft;
my @choices;
my @answers;

sub expand_hash {
	my ($source, $dest, $end_label, $markers, $option_trans, $verbose) = @_;

	my $line;
	my $qflag;
	my $answer;

	my $sel_choice;
	my @chstack;
	my $chnesting = 0;

SCAN:
	while ($line = <$source>) {
		last if $line eq "#\@$end_label\n";
		#	Suppress erasable comments
		if	(  $line =~ s/#-.*//
			&& $line =~ m/^\s*\n$/
			) {
			next;
		}
		#	Substitute marker value
		if ($line =~ m/%\w+%/) {
			my $line_sub;
			my $failure = 0;
			my $optional_subst = $line =~ m/^#\@U/;
			while	($line =~ s/^(.*?)(%\w+%)//) {
				$line_sub .= $1;
				if (exists($$markers{$2})) {
					$line_sub .= $$markers{$2};
				} else {
					$line_sub .= $2;
					$failure = 1;
					if (!$optional_subst) {
						print "${VTred}ERROR:${VTnorm} unknown $2 substitution marker!\n";
					}
					$line_sub =~ s/^(\s*[^#])/#$1/;
				}
			}
			$line = $line_sub . $line;
			if (!$failure && $optional_subst) {
				$line = substr($line, 3);
			}
		}
		#	Ask a question and get answer
		if ($line =~ m/^#\@Q(\w)?\s(.*)\n/) {
			$qflag = $1;
			$answer = ask_question ($2);
			next;
		}
		#	Substitute answer
		if ($line =~ m/^#\@A ?(.*\n)/) {
			my $model = $1;
			if ($qflag eq "R") {
				$line = '';
				while ("" ne $answer) {
					$line .= $model;
					$line =~ s/\@A/$answer/;
					$answer = get_user_choice
						( $qtext
						, $qdeft
						, $#choices>=0 ? \@choices : undef
						, $#answers>=0 ? \@answers : undef
						);
# 					$answer = get_user_choice($qtext, $qdeft, \@choices, \@answers);
				};
			} else {
				($line = $model) =~ s/\@A/$answer/;
			}
		}
		#	Conditional block
		if ($line =~ m/^#\@begin_([A-Z])\s/) {
			if ($1 eq "M") {			# Test marker existence
				if ($line =~ m/^#\@\w+\s+(!)?(\w+)\s*\n/) {
						if	(  $1 eq "!" && exists($$markers{$2})
							|| $1 ne "!" && !exists($$markers{$2})
							) {	# Skip the block
						skip_cond_block ($source, $line);
					}
					next;
				} else {
					$line =~ m/\s(.*)/;
					print "${VTred}ERROR:${VTnorm} malformed marker test \"$1\"!\n";
				}
			} elsif ($1 eq "O") {			# Test an option
								# Test for value
				if ($line =~ m/^#\@\w+\s+(\w+)([=!])=(\w+)\s*\n/) {
					if (exists($option_trans->{$1})) {
						if (defined($$option_trans{$1})) {
							if	(  $$option_trans{$1} ne $3
									&& $2 eq "="
								|| $$option_trans{$1} eq $3
									&& $2 eq "!"
								) {				# Skip the block
								skip_cond_block ($source, $line);
							}
							next;
						} else {
	# NOTE: if option is not passed, should test behave like
	#		existence test and fail instead of giving an error?
							print "${VTred}ERROR:${VTnorm} option $1 not set!\n";
						}
					} else {
						print "${VTred}ERROR:${VTnorm} invalid option $1!\n";
					}
								# Test for existence
				} elsif ($line =~ m/^#\@\w+\s+(!)?(\w+)\s*\n/) {
					if (exists($$option_trans{$2})) {
						if	(  $1 eq "!" && defined($$option_trans{$2})
							|| $1 ne "!" && !defined($$option_trans{$2})
							) {	# Skip the block
							skip_cond_block ($source, $line);
						}
						next;
					} else {
						print "${VTred}ERROR:${VTnorm} invalid option $2!\n";
					}
				} else {
					$line =~ m/\s(.*)/;
					print "${VTred}ERROR:${VTnorm} malformed option test \"$1\"!\n";
				}
			} elsif (  $1 eq "Y"		# Yes/no question
					|| $1 eq "N"
					) {
				my $deft_answ = $1;
				$line =~ m/^#\@\w+\s+(.*\n)/;
				$answer = ask_question($1);
				skip_cond_block ($source, $line) if ($answer ne $deft_answ);
				next;
			} elsif ($1 eq "C") {		# Choice selection
				push(@chstack, $sel_choice);
				$chnesting++;
				$line =~ m/^#\@begin_C\s+(.*)/;
				$sel_choice = ask_question($1);
				next;
			} elsif ($1 =~ m/[a-z]/) {	# Simple label for later step
			} else {
				$line =~ m/^#\@(\w+)/;
				print "${VTred}ERROR:${VTnorm} unknown $1 conditional block!\n";
			}
		}
		#	End of conditional block
		if ($line =~ m/^#\@end_([A-Z])\s/) {
			if ($1 eq 'C') {
				if ($chnesting > 0) {
					$chnesting--;
					$sel_choice = pop(@chstack);
				} else {
					print "${VTred}ERROR:${VTnorm} improper nesting of conditional block!\n";
					print "${VTred}ERROR:${VTnorm} extraneous \@end_C sentinel!\n";
				}
			}
			next;
		}
		#	Start of alternative
		if ($line =~ m/^#\@case_C\s+(.*)/) {
			if ($1 ne $sel_choice) {	# Skip this alternative
				my $chskip = 0;
				while ($line = <$source>) {
					if (substr($line, 0, 9) eq "#\@begin_C") {
						$chskip++;
						next;
					}
					if (substr($line, 0, 7) eq "#\@end_C") {
						if ($chskip-- > 0) {
							next;
						} else {
							redo SCAN ;
						}
					}
					if (substr($line, 0, 8) eq "#\@case_C") {
						if ($chskip > 0) {
							next;
						} else {
							redo SCAN ;
						}
					}
				}
				print "${VTred}ERROR:${VTnorm} alternative for $1 not closed!\n";
				last;
			}
			next;
		}
		#	Define marker from an option value or an answer
		if ($line =~ m/^#\@D\s+(\w+)=(\@)?(\w+)\s*\n/) {
			if ($2 eq '@') {
				if ($3 eq "A") {
					$$markers{"\%$1\%"} = $answer;
				} elsif ($3 eq "C") {
					$$markers{"\%$1\%"} = $sel_choice;
				} else {
					print "${VTred}ERROR:${VTnorm} invalid internal variable $3 in define!\n";
				}
			} elsif (exists($$option_trans{$3})) {
				if (defined($$option_trans{$3})) {
					$$markers{"\%$1\%"} = $$option_trans{$3};
					next;
				} else {
					print "${VTred}ERROR:${VTnorm} option $3 not set for define!\n";
				}
			} else {
				print "${VTred}ERROR:${VTnorm} invalid option $3 in define!\n";
			}
			next;
		}
		#	Verbose message
		if ($line =~ s/#\@V/${VTyellow}***${VTnorm}/) {
			print $line if ($verbose);
			next;
		}

		print $dest $line;
	}
}

##############################################################
#
#				Auxiliary routines
#
##############################################################

#	skip_cond_block skips lines until a matching "label"
#	is found.
#	To preserve future possible extensions, it looks for
#	nested blocks and takes care of them.
sub skip_cond_block {
	my ($fh, $end_line) = @_;

	$end_line = substr($end_line, 0, 9);
	$end_line =~ s/begin/end/;

	my $nesting = 0;
	my @stack;
	while (my $line = <$fh>) {
		if ($line =~ m/^$end_line/) {
			return if $nesting == 0;
			$nesting--;
			$end_line = pop(@stack);
		}
		if ($line =~ m/^#\@begin_[A-Z]/) {
			push(@stack, $end_line);
			$nesting++;
			$end_line = substr($line, 0, 9);
			$end_line =~ s/begin/end/;
		}
	}
	print "${VTred}ERROR:${VTnorm} improper nesting of conditional block!\n";
	print "${VTred}ERROR:${VTnorm} still expecting $end_line sentinel!\n";
}

#	ask_question requests an answer from user.
#	Since the same question may be asked repeatedly,
#	the question parameters are saved in global variables
#	$qtext, $qdeft, @choices and @answers.
sub ask_question {
	my $choices;
	my $answer;

	$#choices = -1;
	$#answers = -1;
	($qtext, $qdeft, $choices, $answer) = split(/;/, shift);
	if (defined($choices)) {
		@choices = map({s/^\s*(.*)\s*$/$1/; $_} split(/,/, $choices));
	}
	if (defined($answer)) {
		@answers = map({s/^\s*(.*)\s*$/$1/; $_} split(/,/, $answer));
	}
	$answer = get_user_choice
		( $qtext
		, $qdeft
		, defined($choices) ? \@choices : undef
		, defined($answer) ? \@answers : undef
		);
	return $answer;
}

1;
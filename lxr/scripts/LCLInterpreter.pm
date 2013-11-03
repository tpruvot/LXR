# -*- tab-width: 4 -*-
###############################################
#
# $Id: LCLInterpreter.pm,v 1.2 2013/01/21 10:49:36 ajlittoz Exp $
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

# $Id: LCLInterpreter.pm,v 1.2 2013/01/21 10:49:36 ajlittoz Exp $

package LCLInterpreter;

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT = qw(
	&expand_hash
	&expand_slash_star
	&pass2_hash
	&pass2_slash_star
);

use strict;
# use File::Path;
use lib do { $0 =~ m{(.*)/}; "$1" };
use QuestionAnswer;
use VTescape;

##############################################################
#
#	LXR Control Language Interpreter
#
##############################################################

# LCL is embedded inside file comments. The exact nature of a
# 'comment' is defined by the derived classes which hand over
# the comment content for interpretation.

# A comment is an LCL candidate if it has the following form:
#	1. Comment starts in column 1
#		This allows to have arbitrary comment anywhere else,
#		even if it looks like an LCL statement.
#	2. @ immediately follows the starting comment delimiter
#	3. The rest of the comment will be scanned by the interpreter.

# *** LCL statements ***

# == Syntax ==

# = Comment =
# Beware that the parser is very very simple. The commands cannot contain
# any form of comment. This would severely disturb the expression scanner.

# = Label: @<label>:[<label:] =
# <label> is a string of a-zA-Z0-9_ followed by a colon, without
# intervening whitespace. If more than one label is needed, repeat the
# construct without intervening whitespace.

# NOTE: in the present implementation, labels cannot prefix a command.
#		In context where labels are meaningful (i.e. @CASE blocks), the
#		line containing the label is eaten up by skipping code. When
#		control is returned to the interpreter, this line is lost.
#		It can no longer trigger any action.

# = Statement: @<name> [<arguments>]
# <name> is an alphanumeric string. Case is indifferent.
# The following sections list the known statements.
# An error is issued for an unknown statement .

# == Message display ==
# @LOG    message
# @MSG    message
# @REMIND message
# @ERROR  message
# These statements print their argument depending on "verbosity".
# @ERROR and @REMIND are always displayed, @LOG is displayed under moderate
# verbosity and @MSG under full verbosity.
# Note that message does not require delimiters. Everything after the
#	whitespace following command name is part of the message.

# == Conditional commands ==
# Conditional blocks may be nested.
# @IF     <expr>
# @ELSEIF <expr>
# @ELSE
# @ENDIF

# @CASE <variable>
# <Label>
# @ENDC

# == User interaction ==
# Single shot, with input kept in <var>:
# @ASK[,<var>] <question>; <kind>; <choices>; <answers>

# Continuous until empty answer, with input kept in <var>: 
# @KEEPON[,<var>] <question>[; -2]
# @ON first
# @ENDON
# @ON last
# @ENDON
# @ON none
# @ENDON
# @ENDK

# By convention, <var> name is a single uppercase letter.

# kind defines the expected answer:
#  -3 any, empty string allowed
#  -2 any but empty string is not allowed
#  -1 any, empty string implies default answer
#   0 one among choices, empty string not allowed
# i>0 one among choices, empty string means choice number i
# choices is empty for -2 and -3
# answers provides "normalised" answers corresponding to choices.
#  If kind=-1, must define a default answer (possibly empty).
# choices and answers are comma-separated lists.
# Answer to question is stored for use in <var>, by default A.

# The lines between @KEEPON and @ENDK are repetitively interpreted
# with <var> containing the most recent "answer" from the user.
# @KEEPON implicitly uses a -3 "kind" since it is necessary to allow a
# "bare" empty answer to exit the loop.

# @KEEPON blocks may be nested in other conditional blocks and may
# contain arbitrary content, including other @KEEPON blocks.

# == Variable definition ==
# @DEFINE <var>=<expr>
# Define a %marker% (% characters are internally added) equal to the
# value of an expression.
# Afterwards, %marker% can be used for substitution.
# NOTE:	since the simple parser only allows for A-Za-z0-9_ characters
#		in both marker and option, a translation is needed between the
#		shell option name and the #@D option name.
#		This is done through the hash reference $option_trans, i.e.
#		$$option_trans{'option'} gives the value to use.

# == Shell command insertion ==
# @XQT <shell command>
# Insert <shell command> into the output stream when generating for a
# shell (i.e. marker %_shell% defined and non zero).

# == File inclusion ==
# @ADD <filename>
# Interpretation continues inside <filename> which may itself contain
# other @ADD commands.
# Limitations:
#	1.	@ADD is effective only when met while interpreting. @ADD is not
#		taken into account when it appears inside skipped blocks (inactive
#		branch of @IF/@ELSE/@ENDIF or unselected case of @CASE/@ENDK, ...)
#	2.	Consequence of 1., do not open any block (@CASE, @IF, @KEEPON,
#		@PASS2) in one file and put the closing command in another file.
#		Due to the possible skip of intervening statements, the @ADD
#		containing the opening orclosing statement might be not
#		interpreted and the stream will appear incorrectly bracketed.
# File name path: the current directory is the one in effect when the
#	configurator is launched. It might be better to use OS-absolute paths.

# == Delayed interpretation ==
# @PASS2[,R] <label>
# @ENDP2
# Mark a block for later interpretation (mainly used to add tree
# specific sections into the output stream).
# @PASS2 blocks cannot be nested.
# During pass 1, add label <label> into the output stream and skip
# interpretation of block.
# During pass 2 and following, template is read sequentially for @PASS2.
# When one is found, output stream is advanced up to the corresponding
# label which is replaced by the interpreted content of block and <label>
# is written again, unless option R (= remove after use) is specified
# (thus allowing single shot expansions).
# Other @PASS2 blocks are looked for until EOF.
# NOTE:	Due to the scanning difference between pass 1 and 2, statements
#		@PASS2 and @ENDP2 must not be coded inside @ADD'ed files or
#		nested in @IF, @CASE or @KEEPON blocks.
#		@PASS2 blocks may contain @ASK or @KEEPON statements, but this
#		is not recommended unless they are preceded by explicit @LOG
#		or @MSG clearly showing we are in pass 2.


##############################################################
#
#	Part 1: template file expansion
#
##############################################################

my $addnestingmax = 5;
my $addnesting;		# To prevent infinite @ADD

sub expand_hash {
	my @args = @_;
	$addnesting = 0;
	expand	( @args
			, '#', ''
			, '~~~TO~EOF~~~'	# Hope this is never used as a label!
			);
}

sub expand_slash_star {
	my @args = @_;
	$addnesting = 0;
	expand	( @args
			, qr(/\*), qr(\*/)
			, '~~~TO~EOF~~~'	# Hope this is never used as a label!
			);
}

sub expand {
	my ($source, $dest, $markers, $verbose, $comstart, $comend, $end_label) = @_;
	my $line;

SCAN:
	while ($line = &$source()) {
		# 	Are we done?
		return parse_statement ($line, $comstart, $comend)
			if $line =~ m/^${comstart}\@$end_label/;

		#	Suppress erasable comments
		if ($comend eq '') {
			if	(  $line =~ s/${comstart}-.*//
				&& $line =~ m/^\s*\n$/
				) {
				next;
			}
		} else {
			if ($line =~ m:${comstart}-:) {
				$line =~ s:(.*?)${comstart}-::;
				my $linehead = $1;
				if ($line =~ s:.*?-${comend}::) {
					$line = $linehead . $line;
					redo SCAN if $line !~ m/^\s*\n$/;
				} else {
					if ($linehead !~ m/^\s*$/) {
						print $dest $linehead, "\n";
					}
					while ($line = &$source()) {
						if ($line =~ m:-${comend}:) {
							$line =~ s:.*?-${comend}::;
							redo SCAN if $line !~ m/^\s*\n$/;
							last;
						}
					}
				}
				next;
			}
		}


		#############################################
		#
		#			Statement interpreter
		#
		#############################################
		#	Is this an LCL statement?
		if ($line =~ m/^${comstart}@/) {
			my ($args, $var, $command, @labels)
				= parse_statement($line, $comstart, $comend);

			if ($command eq '') {		# Label only?
				# Keep it in output file (NOTE: should not occur)

										# Fault-tolerant substitution line
			} elsif ($command eq 'U') {
				# Is processed below

										# Shell command
			} elsif ($command eq 'XQT') {
				if ($$markers{'%_shell%'}) {
					$line =~ s:^${comstart}\@${command}\s(.*)\s*${comend}\s*\n:$1\n:;
				} #else {		# Uncomment to remove line from output
				#	next;
				#}
				# Is further processed below

										# Messages
			} elsif ($command eq 'ERROR') {
				substitute_markers (\$args, $markers, $comstart, $comend);
				print "${VTred}ERROR:${VTnorm} $args\n";
				next;
			} elsif ($command eq 'REMIND') {
				substitute_markers (\$args, $markers, $comstart, $comend);
				print "${VTyellow}Reminder:${VTnorm} $args\n";
				next;
			} elsif ($command eq 'LOG') {
				substitute_markers (\$args, $markers, $comstart, $comend);
				print "${VTyellow}***${VTnorm} $args\n" if $verbose;
				next;
			} elsif ($command eq 'MSG') {
				substitute_markers (\$args, $markers, $comstart, $comend);
				print "${VTyellow}***${VTnorm} $args\n" if $verbose > 1;
				next;

										# User interaction
			} elsif ( $command eq 'ASK') {
				substitute_markers (\$args, $markers, $comstart, $comend);
				$$markers{"%$var%"} = ask_question($args);
				next;
			} elsif ($command eq 'KEEPON') {
				my %keep;
				if ($args =~ s/;\s*(-\d+)$//) {
					if ($1 != -2 && $1 != -3) {
						print "${VTred}ERROR:${VTnorm} illegal type $1 question for \@KEEPON!\n";
						$args .= ';-3';
					} else {
						$args .= ";$1";
					}
				} else {
					$args .= ';-3';
				}
				substitute_markers (\$args, $markers, $comstart, $comend);
				$keep{'q'} = $args;
				$keep{'v'} = $var;
				my @kbody;
				while ($command ne 'ENDK') {
					$line = &$source();
					if ($line =~ m/${comstart}\@/) {
						($args, $var, $command, @labels)
							= parse_statement($line, $comstart, $comend);
						last if $command eq 'ENDK';
						if ($command eq 'ON') {
							my ($type) = $args =~ m/^(\w+)(?:\s|$)/;
							$type = lc($type);
							if	(  $type ne 'first'
								&& $type ne 'last'
								&& $type ne 'none'
								) {
								print "${VTred}ERROR:${VTnorm} unknown $type KEEPON action type!\n";
								skip_until	( $source
											, qr/ENDON\b/i
											, 'KEEPON', 'ENDK'
											, $comstart, $comend
											)
							} else {
								$keep{$type} = [ grab_block
									( $source
									, qr/ENDON\b/i
									, 'KEEPON', 'ENDK'
									, $comstart, $comend
									) ];
							}
						} elsif ($command eq 'KEEP') {
							push	( @kbody
									, grab_block	( $source
													, qr/ENDK\b/i
													, 'KEEPON', 'ENDK'
													, $comstart, $comend
													)
									);
						} else {
							push (@kbody, $line);
						}
					} else {
						push (@kbody, $line);
					}
				}
				$keep{'body'} = [ @kbody ];
				my $answer = ask_question($keep{'q'});
				$$markers{"%${keep{'v'}}%"} = $answer;
				$keep{'q'} =~ s/;-2$/;-3/; # Ensure loop can be left
				if ($answer eq '') {
					# initial answer is empty, block is skipped.
					# See if action 'none' should be triggered.
					if (exists($keep{'none'})) {
						@kbody = @{$keep{'none'}};
						expand	( sub { pop(@kbody) }
								, $dest
								, $markers
								, $verbose
								, $comstart, $comend
								, '~~~TO~EOF~~~'
								);
					}
					next;
				}
				if (exists($keep{'first'})) {
						@kbody = @{$keep{'first'}};
						expand	( sub { pop(@kbody) }
								, $dest
								, $markers
								, $verbose
								, $comstart, $comend
								, '~~~TO~EOF~~~'
								);
				}
				while ($answer ne '') {
					@kbody = @{$keep{'body'}};
					expand	( sub { pop(@kbody) }
							, $dest
							, $markers
							, $verbose
							, $comstart, $comend
							, '~~~TO~EOF~~~'
							);
					$answer = ask_question($keep{'q'});
					$$markers{"%${keep{'v'}}%"} = $answer;
				}
				if (exists($keep{'last'})) {
						@kbody = @{$keep{'last'}};
						expand	( sub { pop(@kbody) }
								, $dest
								, $markers
								, $verbose
								, $comstart, $comend
								, '~~~TO~EOF~~~'
								);
				}
				next;

										# Conditional block
			} elsif ($command eq 'IF') {
				while ($command ne 'ENDIF')
				{	if	(  $command eq 'ELSE'
						|| evaluate_expr($args, $markers)
						)
					{	($args, $var, $command, @labels)
							= expand	( $source, $dest
										, $markers
										, $verbose
										, $comstart, $comend
										, qr/\s*(ELSE(IF)?|ENDIF)\b/i
										)
					;	if ($command ne 'ENDIF')
						{	skip_until	( $source
										, qr/ENDIF\b/i
										, 'IF', 'ENDIF'
										, $comstart, $comend
										)
						}
					;	last
					}
				;	($args, $var, $command, @labels)
						= skip_until	( $source
										, qr/(ELSE(IF)?|ENDIF)\b/i
										, 'IF', 'ENDIF'
										, $comstart, $comend
										)
				}
				next;

										# Selection block
			} elsif ($command eq 'CASE') {
				my $thecase = evaluate_expr($args, $markers);
				while (1)
				{	($args, $var, $command, @labels)
						= skip_until	( $source
										, qr/(\w+):/
										, 'CASE', 'ENDC'
										, $comstart, $comend
										)
				;	if ($command eq 'ENDC')
					{	print "${VTred}ERROR:${VTnorm} no '$thecase' case label!\n";
					;	last
					}
				;	if (grep {$thecase eq $_} @labels)
					{	($args, $var, $command, @labels)
							= expand	( $source, $dest
										, $markers
										, $verbose
										, $comstart, $comend
										, qr/((\w+):|((?i)\s*ENDC\b))/
										)
					;	if ($command ne 'ENDC')
						{	skip_until	( $source
										, qr/ENDC\b/i
										, 'CASE', 'ENDC'
										, $comstart, $comend
										)
						}
					;	last
					}
				}
				next;

										# Symbol definition
			} elsif ( $command eq 'DEFINE') {
				my ($var, $string) = ($args =~ m/^(\w+)\s*=\s*(.+)/);
				if (substr($var, 0, 1) eq '_') {
					print "${VTred}ERROR:${VTnorm} can't set read-only variable $var!\n";
				} else {
					$$markers{"\%$var\%"} = evaluate_expr($string, $markers);
				}
				next;

										# Include a file
			} elsif ($command eq 'ADD') {
				if (!defined($args)) {
					print "${VTred}ERROR:${VTnorm} no file target on ADD!\n";
					next;
				}
				if ($addnesting >= $addnestingmax) {
					print "${VTred}ERROR:${VTnorm} too many nested ADD files with \"${args}\"\n";
					next;
				}
				my ($string) = ($args =~ m/^["']?(.+)["']?$/);
				$string = evaluate_expr("\"$string\"", $markers);
				if (open(ADD, '<', $string)) {
					++$addnesting;
					expand	( sub { <ADD> }
							, $dest
							, $markers
							, $verbose
							, $comstart, $comend
							, '~~~TO~EOF~~~'
							);
					--$addnesting;
				} else {
					print "${VTred}ERROR:${VTnorm} couldn't open ADD'ed file \"${string}\"\n";
				}
				close ADD;
				next;

										# Block for pass 2
			} elsif ($command eq 'PASS2') {
				if (!defined($args)) {
					if ('R' eq $var) {
						print "${VTred}ERROR:${VTnorm} PASS2 must define a label replacement for the block!\n";
					}
					$args = 'courtesy_label';
				}
				# Replace block with a label unlessoption R and adding trees
				if	(	'R' ne $var
					||	0 == $$markers{'%_add%'}
					) {
					$line =~ s/^(${comstart}\@).+(${comend})\s*\n/$1${args}:$3\n/;
				}
				skip_until	( $source
							, qr/ENDP2\b/i
							, '~~~TO~EOF~~~', '~~~TO~EOF~~~'
							, $comstart, $comend
							)

			} elsif (  $command eq 'ELSE'
					|| $command eq 'ELSEIF'
					|| $command eq 'ENDIF'
					|| $command eq 'ENDC'
					|| $command eq 'ENDK'
					|| $command eq 'ON'
					|| $command eq 'ENDON'
					|| $command eq 'PASS2'
					) {
				print "${VTred}ERROR:${VTnorm} spurious $command!\n";
				next;

			} else {					# Unknown LCL statement
				print "${VTred}ERROR:${VTnorm} unknown command $command!\n";
				next;
			}
		}

		#	Substitute marker value
		substitute_markers (\$line, $markers, $comstart, $comend);

		print $dest $line;
	}
}


##############################################################
#
#	Part 2: special block expansion/insertion for
#			second and eventual subsequent passes
#
##############################################################

sub pass2_hash {
	my @args = @_;
	pass2 (@args, '#', '');
}

sub pass2_slash_star {
	my @args = @_;
	pass2 (@args, qr(/\*), qr(\*/));
}

sub pass2 {
	my ($source, $dest, $markers, $verbose, $comstart, $comend) = @_;
	my $line;

	unless (open(DESTIN, '<', $dest)) {
		die("${VTred}ERROR:${VTnorm} couldn't reread output file \"$dest\"\n");
	}
	unless (open(DESTOUT, '>', "$dest.LXR")) {
		die("${VTred}ERROR:${VTnorm} couldn't open temporary file \"$dest\"\n");
	}

	$addnesting = 0;
	while ($line = <$source>) {
		if ($line =~ m/^${comstart}\@\s*PASS2\b/) {
			my ($args, $var, $command, @labels)
				= parse_statement($line, $comstart, $comend);
			if (!defined($args)) {
				if ('R' eq $var) {
					print "${VTred}Warning:${VTnorm} using a courtesy label for missing PASS2 label!\n";
				}
				$args = 'courtesy_label';
			}
			my $mark_label = $line;
			$mark_label =~ s/^(${comstart}\@).+(${comend})\s*\n/$1${args}:$2\n/;

			# Position destination file on corresponding label
			while (<DESTIN>) {
				last if m/^${comstart}\@$args:/;
				print DESTOUT $_;
			}
			if (!defined($line)) {
				print  "${VTred}Error:${VTnorm} label $args not found in destination file!\n";
				return;
			}
			# Expand dedicated block
			expand	( sub { <$source> }, \*DESTOUT
					, $markers
					, $verbose
					, $comstart, $comend
					, qr/s*ENDP2\b/i
					);
			# Rewrite lable for eventual other passes
			print DESTOUT $mark_label if 'R' ne $var;
		}
	}

	# Copy rest of destination file
	while (<DESTIN>) {
		print DESTOUT $_;
	}
	# Switch files
	close(DESTIN);
	close(DESTOUT);
	unlink $dest;
	rename "$dest.LXR", $dest;
}


##############################################################
#
#				Auxiliary routines
#
##############################################################

#	parse_statement splits an LCL statement into components
#	Command name is uppercased to ease processing independent of
#	case. If no variable is defined, a default A is provided.
sub parse_statement {
	my ($line, $comstart, $comend) = @_;
	$line =~ s/^${comstart}@//;	# Get rid of prefix
	my @labels;
	while ($line =~ s/^(\w+)://g) {	# Grab labels
		push @labels, $1;
	}
	$line =~ s/^\s*(\w+)//;		# Grab command name
	my $command = uc($1);
	my $var = 'A';				# Grab var name
	$var = $1  if $line =~ s/^,(\w+)//;
	my ($args) = ($line =~ m/^\s+(.*)\s*${comend}\s*\n/);
	return ($args, $var, $command, @labels);
}

#	substitute_markers replaces %xxx% occurrences by value of
#	marker xxx. If original string is prefixed by LCL command
#	@U, no error is issued for unknown marker and command prefix is
#	left in place (so that the string looks like a comment),
#	otherwise the @U command is transformed into a common string.
sub substitute_markers {
	my ($line, $markers, $comstart, $comend) = @_;

	if ($$line =~ m/%\w+%/) {
		my $line_sub;
		my $failure = 0;
		my $optional_subst = $$line =~ m/^${comstart}\@U/;
		while	($$line =~ s/^(.*?)(%\w+%)//) {
			$line_sub .= $1;
			if (exists($$markers{$2})) {
				$line_sub .= $$markers{$2};
			} else {
				$line_sub .= $2;
				$failure = 1;
				if (!$optional_subst) {
					print "${VTred}ERROR:${VTnorm} unknown $2 substitution marker!\n";
				}
			}
		}
		$$line = $line_sub . $$line;
		if	(  !$failure && $optional_subst
			&& $$line =~ s/^${comstart}\@U//
			) {
			$$line =~ s/\s*${comend}\s*\n/\n/;
		}
	}

}

#	evaluate_expr evaluate its argument as a Perl expression
#	(mainly string comparisons).
#	Occurrences of %xxx% are transformed into local string variables.
# NOTE: do not abuse expression complexity! The configurator may
#		some day be rewritten in another language where expression
#		evaluation will have to be programmed. Its power will certainly
#		be limited to basic needs such as string comparison and logical
#		combination.
sub evaluate_expr {
	my ($expr, $markers) = @_;
	my %exprvars;
	my $theeval;

	# List used variables and check for illegal computation
	# NOTE: $op can be extended for more complex valid expressions
	my $op = qr/(?:eq|ne)/;
	while ($expr =~ m/($op\s*)?%(\w+)%(\s*$op)?/g) {
		# Make a difference between test for existence/definedness and
		# usage in a comparison/computation where value is needed
		if	(	(defined($1) || defined($3))
			&&	!exists($$markers{"\%$2\%"})) {
			print "${VTred}ERROR:${VTnorm} unknown $2 substitution marker!\n";
		}
	};
	my @allvars = ($expr =~ m/%(\w+)%/g);
	for (@allvars) {
		$exprvars{$_} = 1;
	}
	# Build the expression to evaluate
	$expr =~ s/%(\w+)%/\$\{_${1}_\}/g;
	foreach my $newvar (keys %exprvars) {
		$theeval .= 'my $_' . $newvar . '_ = "' . $$markers{"\%$newvar\%"} . '"; ';
	}
	$theeval .= $expr;
	my $res = eval($theeval);
	if ($@) {
		print "${VTred}ERROR:${VTnorm} bad expression: $@";
		print "${VTyellow}$expr${VTnorm}\n";
		return undef;
	}
	return $res;
}

#	skip_until skips lines until a matching sentinel
#	is found. It takes care of nested blocks.
sub skip_until {
	my ($source, $sentinel, $begin, $end, $comstart, $comend) = @_;

	my $stop;
	if ($sentinel =~ m/\):/) {
		$stop       = qr/^${comstart}\@${sentinel}/;
	} else {
		$stop       = qr/^${comstart}\@\s*${sentinel}/;
	}
	my $start_block = qr/^${comstart}\@\s*${begin}\b\s/i;
	my $end_block   = qr/^${comstart}\@\s*${end}\b/i;

	my $nesting = 0;
	while (my $line = &$source()) {
		if ($line =~ m/$end_block/) {
			return parse_statement($line, $comstart, $comend)
				if $nesting == 0;
			$nesting--;
			next;
		}
		if ($line =~ m/$start_block/) {
			$nesting++;
			next;
		}
		if	(  $nesting == 0
			&& $line =~ m/$stop/
			) {
			return parse_statement($line, $comstart, $comend);
		}
	}
	print "${VTred}ERROR:${VTnorm} improper nesting of conditional block!\n";
	print "${VTred}ERROR:${VTnorm} still expecting $stop sentinel!\n";
	die "Conditional block overflow";
}

#	grab_block stores lines until a matching sentinel
#	is found. It takes care of nested blocks.
sub grab_block {
	my ($source, $sentinel, $begin, $end, $comstart, $comend) = @_;
	my @blocklines;

	my $stop;
	if ($sentinel =~ m/\):/) {
		$stop       = qr/^${comstart}\@${sentinel}/;
	} else {
		$stop       = qr/^${comstart}\@\s*${sentinel}/;
	}
	my $start_block = qr/^${comstart}\@\s*${begin}\s/i;
	my $end_block   = qr/^${comstart}\@\s*${end}\b/i;

	my $nesting = 0;
	while (my $line = &$source()) {
		if ($line =~ m/$end_block/) {
# Finding an end-of-block sentinel before the correct termination
# is an error when recording sample code. This will be catched
# at EOF (or, at least, I hope).
#			return @blocklines if $nesting == 0;
			$nesting--;
			next;
		}
		if ($line =~ m/$start_block/) {
			$nesting++;
			next;
		}
		if	(  $nesting == 0
			&& $line =~ m/$stop/
			) {
			return @blocklines;
		}
		push @blocklines, $line;
	}
	print "${VTred}ERROR:${VTnorm} improper sample block limits!\n";
	print "${VTred}ERROR:${VTnorm} still expecting $sentinel sentinel!\n";
	die "Sample block overflow";
}

#	ask_question requests an answer from user.
#	This is an interface to get_user_choice in QuestionAnswer.pm
sub ask_question {
	my ($qtext, $qdeft, $choices, $answer);
	my (@choices, @answers);

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
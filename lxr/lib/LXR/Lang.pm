# -*- tab-width: 4; cperl-indent-level: 4 -*- ###############################################
#
# $Id: Lang.pm,v 1.39 2011/03/12 13:10:29 ajlittoz Exp $

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

package LXR::Lang;

$CVSID = '$Id: Lang.pm,v 1.39 2011/03/12 13:10:29 ajlittoz Exp $ ';

use strict;
use LXR::Common;

sub new {
	my ($self, $pathname, $releaseid, @itag) = @_;
	my ($lang, $type);

	foreach $type (values %{ $config->filetype }) {
		if ($pathname =~ /$$type[1]/) {
			eval "require $$type[2]";
			die "Unable to load $$type[2] Lang class, $@" if $@;
			my $create = "new $$type[2]" . '($pathname, $releaseid, $$type[0])';
			$lang = eval($create);
			die "Unable to create $$type[2] Lang object, $@" unless defined $lang;
			last;
		}
	}

	if (!defined $lang) {

		# Try to see if it's a #! script or an emacs mode-tagged file
		my $fh = $files->getfilehandle($pathname, $releaseid);
		return undef if !defined $fh;
		my $line = $fh->getline;
		($line =~ /^\#!\s*(\S+)/s)
		|| ($line =~ /^.*-[*]-.*?[ \t;]mode:[ \t]*(\w+).*-[*]-/);

		my $shebang  = $1;
		my %filetype = %{ $config->filetype };
		my %inter    = %{ $config->interpreters };

		foreach my $patt (keys %inter) {
			if ($shebang =~ /$patt$/) {
				eval "require $filetype{$inter{$patt}}[2]";
				die "Unable to load $filetype{$inter{$patt}}[2] Lang class, $@" if $@;
				my $create = "new "
				  . $filetype{ $inter{$patt} }[2]
				  . '($pathname, $releaseid, $filetype{$inter{$patt}}[0])';
				$lang = eval($create);
				last if defined $lang;
				die "Unable to create $filetype{$inter{$patt}}[2] Lang object, $@";
			}
		}
	}

	# No match for this file
	return undef if !defined $lang;

	$$lang{'itag'} = \@itag if $lang;

	return $lang;
}

sub processinclude {
	my ($self, $frag, $dir) = @_;
	my $source = $$frag;

	# Split the include directive into individual components
	$source =~ s/^					# reminder: no initial space in the grammar
				([\w\#]\s*[\w]*)	# reserved keyword for include construct
				(\s+)				# space
				(?|	(\")(.+?)(\")	# C syntax
				|	(\0<)(.+?)(\0>)	# C alternate syntax
				|	()([\w:]+)(\b)	# Perl and others
				)
				//sx ;
	# Now, process individually the component to avoid marking
	#	inadvertantly HTML tags if a user identifier is same as one
	# NOTE: processreserved is inlined to proceed with the different
	#		markings simultaneously to avoid interferences;
	#		second reason, $2 is not a reference
	$$frag =	( $self->isreserved($1)
				? "<span class='reserved'>$1</span>"
				: "$1"
				)
			.	"$2$3"
			.	&LXR::Common::incref($4, "include" ,$4 ,$dir)
			.	"$5"
			. $source;		# tail if any (e.g. in Perl)
}

sub processcomment {
	my ($self, $frag) = @_;

	$$frag = "<span class=\"comment\">$$frag</span>";
	$$frag =~ s#\n#</span>\n<span class=\"comment\">#g;
	$$frag =~ s#<span class=\"comment\"></span>$## ; #remove excess marking
}

#
# Stub implementations of this interface
#

sub processcode {
	my ($self, $code) = @_;
	warn  __PACKAGE__."::processcode not implemented. Parameters @_";
	return;
}

sub processreserved {
	my ($self, $frag) = @_;
	warn  __PACKAGE__."::processreserved not implemented. Parameters @_";
	return;
}

sub referencefile {
	my ($self, $name, $path, $fileid, $index, $config) = @_;
	warn  __PACKAGE__."::referencefile not implemented. Parameters @_";
	return;
}

sub language {
	my ($self) = @_;
	my $languageName;
	warn  __PACKAGE__."::language not implemented. Parameters @_";
	return $languageName;
}

1;

# -*- tab-width: 4 -*- ###############################################
#
# $Id: Config.pm,v 1.40 2011/12/23 20:01:19 ajlittoz Exp $

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

package LXR::Config;

$CVSID = '$Id: Config.pm,v 1.40 2011/12/23 20:01:19 ajlittoz Exp $ ';

use strict;
use File::Path;

use LXR::Common;

require Exporter;

use vars qw($AUTOLOAD $confname);

$confname = 'lxr.conf';

sub new {
	my ($class, @parms) = @_;
	my $self = {};
	bless($self);
	$self->_initialize(@parms);
	return ($self);
	die("Foo!\n");
}

sub readfile {
	local ($/) = undef;    # Just in case; probably redundant.
	my $file = shift;
	my @data;

	open(INPUT, $file) || fatal("Config: cannot open $file\n");
	$file = <INPUT>;
	close(INPUT);

	@data = $file =~ /([^\s]+)/gs;

	return wantarray ? @data : $data[0];
}

sub _initialize {
	my ($self, $url, $confpath) = @_;
	my ($dir,  $arg);

	unless ($url) {
		$url = 'http://' . $ENV{'SERVER_NAME'} . ':' . $ENV{'SERVER_PORT'};
		$url =~ s/:80$//;
	}

	$url =~ s!^//!http://!;		# allow a shortened form in genxref
	$url =~ s!^http://([^/]*):443/!https://$1/!;
	$url .= '/' unless $url =~ m#/$#;    # append / if necessary

	unless ($confpath) {
		($confpath) = ($0 =~ /(.*?)[^\/]*$/);
		$confpath .= $confname;
	}

	unless (open(CONFIG, $confpath)) {
		die("Couldn't open configuration file \"$confpath\".");
	}

	$$self{'confpath'} = $confpath;

	local ($/) = undef;
	my $config_contents = <CONFIG>;
	$config_contents =~ /(.*)/s;
	$config_contents = $1;    #untaint it
	my @config = eval("\n#line 1 \"configuration file\"\n" . $config_contents);
	die($@) if $@;

	my $config;
	if (scalar(@config) > 0) {
		%$self = (%$self, %{ $config[0] });
	}

	$url =~ m!(.*?://.*?)/!;	# host name and port used to access server
	my $host = $1;
	my $script_path;
	if ($url) {
		($script_path = $url) =~ s!^.*?://[^/]*!!; # remove host and port
	} else {
		$script_path = $ENV{'SCRIPT_NAME'};
	}
	$script_path =~ s!/[^/]*$!!;	# path to script
	$script_path =~ s!^/*!/!;		# ensure a single starting /
  CANDIDATE: foreach $config (@config[1..$#config]) {
		my @hostnames;
		if (exists($config->{'host_names'})) {
			@hostnames = @{$config->{'host_names'}};
		} elsif (exists($self->{'host_names'})) {
			@hostnames = @{$self->{'host_names'}};
		};
		my $virtroot = $config->{'virtroot'};
		my $hits = $virtroot =~ s!/+$!!;	# ensure no ending /
		$hits += $virtroot =~ s!^/+!/!;		# and a single starting /
		if ($hits > 0) { $config->{'virtroot'} = $virtroot }
		if (scalar(@hostnames)>0) {
			foreach my $rt (@hostnames) {
				$rt =~ s!/*$!!;		# remove trailing /
				$rt =~ s!^//!http://!; # allow for a shortened form
				if	(	$host eq $rt
					&&	$script_path eq $virtroot
					) {
					$config->{'baseurl'} = $rt . $script_path;
					%$self = (%$self, %$config);
					last CANDIDATE;
				}
			}
		} else { # elsif ($config->{'baseurl'}) {
			my @aliases;
			if ($config->{'baseurl_aliases'}) {
				@aliases = @{ $config->{'baseurl_aliases'} };
			}
			my $root = $config->{'baseurl'};
			push @aliases, $root;
			foreach my $rt (@aliases) {
				$rt .= '/' unless $rt =~ m#/$#;    # append / if necessary
				my $r = quotemeta($rt);
				if ($url =~ /^$r/) {
					$config->{'baseurl'} = $rt;
					%$self = (%$self, %$config);
					last CANDIDATE;
				}
			}
		}
	}

	$$self{'encoding'} = "iso-8859-1" unless (exists $self->{'encoding'});

	if(!exists $self->{'baseurl'}) {
		if("genxref" ne ($0 =~ /([^\/]*)$/)) {
			return 1;
		}
		elsif($url =~ m!https?://.+\.!) {
			die "Can't find config for $url: make sure there is a 'baseurl' line that matches in lxr.conf\n";
		} else {	
			# wasn't a url, so probably genxref with a bad --url parameter
			die "Can't find config for $url: " . 
			 	"the --url parameter should be a URL (e.g. http://example.com/lxr) and must match a baseurl line in lxr.conf\n";
		}
	}

	# Set-up various directories as necessary
  _ensuredirexists($self->{'tmpdir'});

  if (exists $self->{'glimpsebin'} and exists $self->{'swishbin'}) {
    die "Both Glimpse and Swish have been specified in $confpath.\n".
        "Please choose one or other of them by commenting out either glimpsebin or swishbin.\n";
  } elsif (exists $self->{'glimpsebin'}) {    
    die "Please specifiy glimpsedir in $confpath\n" if !exists $self->{'glimpsedir'};    
    _ensuredirexists($self->{'glimpsedir'});
  } elsif (exists $self->{'swishbin'}) {    
    die "Please specifiy glimpsedir in $confpath\n" if !exists $self->{'swishdir'};    
    _ensuredirexists($self->{'swishdir'});
  } else {
    die "Neither Glimpse nor Swish have been specified in $confpath.\n".
        "Please choose one or other of them by specifing a value for either glimpsebin or swishbin.\n";
  }
}

sub allvariables {
	my $self = shift;

	return keys(%{ $self->{variables} || {} });
}

sub variable {
	my ($self, $var, $val) = @_;

	$self->{variables}{$var}{value} = $val if defined($val);
	return $self->{variables}{$var}{value}
	  || $self->vardefault($var);
}

sub vardefault {
	my ($self, $var) = @_;

	if (exists($self->{variables}{$var}{default})) {
		return $self->{variables}{$var}{default}
	}
	if (ref($self->{variables}{$var}{range}) eq "CODE") {
		my @vr = varrange($var);
		return $vr[0] if scalar(@vr); return "head"
	}
	return	$self->{variables}{$var}{range}[0];
}

sub vardescription {
	my ($self, $var, $val) = @_;

	$self->{variables}{$var}{name} = $val if defined($val);

	return $self->{variables}{$var}{name};
}

sub varrange {
	my ($self, $var) = @_;
	no strict "refs";	# ajl: temporary, I hope. Without it
						# following line fails in $var!

	if (ref($self->{variables}{$var}{range}) eq "CODE") {
		return &{ $self->{variables}{$var}{range} };
	}

	return @{ $self->{variables}{$var}{range} || [] };
}

sub varexpand {
	my ($self, $exp) = @_;
	$exp =~ s/\$\{?(\w+)\}?/$self->variable($1)/ge;

	return $exp;
}

sub value {
	my ($self, $var) = @_;

	if (exists($self->{$var})) {
		my $val = $self->{$var};

		if (ref($val) eq 'ARRAY') {
			return map { $self->varexpand($_) } @$val;
		} elsif (ref($val) eq 'CODE') {
			return $val;
		} else {
			return $self->varexpand($val);
		}
	} else {
		return undef;
	}
}

sub AUTOLOAD {
	my $self = shift;
	(my $var = $AUTOLOAD) =~ s/.*:://;

	my @val = $self->value($var);

	if (ref($val[0]) eq 'CODE') {
		return $val[0]->(@_);
	} else {
		return wantarray ? @val : $val[0];
	}
}

sub mappath {
	my ($self, $path, @args) = @_;
	my %oldvars;
	my ($m, $n);

	foreach $m (@args) {
		if ($m =~ /(.*?)=(.*)/) {
			$oldvars{$1} = $self->variable($1);
			$self->variable($1, $2);
		}
	}

	while (($m, $n) = each %{ $self->{maps} || {} }) {
		$path =~ s/$m/$self->varexpand($n)/e;
	}

	while (($m, $n) = each %oldvars) {
		$self->variable($m, $n);
	}

	return $path;
}

sub _ensuredirexists {
  my $dir = shift;
  if(!-d $dir) {
    mkpath($dir) or die "Couldn't make the directory $dir: ?!";
  }  
}


1;

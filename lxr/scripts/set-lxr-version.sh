#!/bin/bash
# $Id: set-lxr-version.sh,v 1.1 2012/04/03 16:06:27 ajlittoz Exp $

shopt -s extglob
. ${0%%+([^/])}ANSI-escape.sh

#	Strip directory from command
cmdname=${0##*/}

#	Decode options and arguments
version=
user=0
while [[ $# > 0 ]] ; do
	case "$1" in
		--help | -h )
			echo "$cmdname [OPTION]... version-number"
			echo "Sets LXR version to the given number"
			echo "This script is automatically invoked during the release procedure."
			echo "It should be used by an end-user only after making custom changes"
			echo "to tag the copy as non-standard."
			echo
			echo "OPTION:"
			echo "  -h, --help     print this reminder and stop"
			echo "  -u, --user     custom version-number is added to release number"
			echo
			echo "Note: this script gives no error if it can't set the version number"
			exit 0
		;;
		--user | -u )
			user=1
		;;
		--[^-]* | -[^-]* )
			echo "${VTyellow}${cmdname}:${VTnorm} unknown option $1"
		;;
		* )
			version="$1"
		;;
	esac
	shift
done

if [ "x$version" == "x" ] ; then
	echo "${VTred}${cmdname}:${VTnorm} no version" >/dev/stderr
	exit 1
fi

if [[ "$user" == 1 ]] ; then
	sed	-e "/our \$LXRversion =/s/-.*\";/\";/" \
		-e "/our \$LXRversion =/s/\";/-${version}\";/" \
		-i lib/LXRversion.pm

else
	sed	-e "/our \$LXRversion =/s/%LXRRELEASENUMBER%/${version}/" \
		-i lib/LXRversion.pm
fi

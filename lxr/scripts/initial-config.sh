#!/bin/bash
# $Id: initial-config.sh,v 1.9 2012/08/05 11:45:34 ajlittoz Exp $

shopt -s extglob
. ${0%%+([^/])}ANSI-escape.sh

#	Strip directory from command
cmdname=${0##*/}

confdir="lxrconf.d"

#	Decode options and arguments
lxt="lxr.conf"
everything=1
while [[ $# > 0 ]] ; do
	case "$1" in
		--help | -h )
			echo "$cmdname [OPTION]... [lxr-conf-template]"
			echo "Sets up the initial content of ${confdir} and copies tree-independent"
			echo "files to their proper location"
			echo
			echo "OPTION:"
			echo "  -h, --help     print this reminder and stop"
			echo "  -a, --add      only add new master configuration file"
			echo "                 (omits all other files)"
			echo
			echo "lxr-conf-template  LXR master configuration template name in templates/"
			echo "                   sub-directory (defaults to lxr.conf if not specified)"
			exit 0
		;;
		--add | -a )
			everything=0
		;;
		--[^-]* | -[^-]* )
			echo "${VTyellow}${cmdname}:${VTnorm} unknown option $1"
		;;
		* )
			lxt="$1"
		;;
	esac
	shift
done

if [[ ! -d "${confdir}" ]] ; then
	mkdir --mode=ug=rwx,o=rx "${confdir}"
fi

if [[ ! -f "templates/$lxt" ]] ; then
	echo "${VTred}${cmdname}: template ${lxt} does not exist!${VTnorm}"
	exit 1
fi

echo "${VTyellow}***${VTnorm} Initial phase configurator for LXR (\$Revision: 1.9 $) ${VTyellow}***${VTnorm}"
echo

if [ "$everything" == 1 ] ; then
	while : ; do
		read -p "Configure for single/multiple trees? [S/m] " cardinality
		if [ "x$cardinality" != "x" ] ; then
			case "$cardinality" in
				"s" | "S" )
					cardinality="s"
					break
				;;
				"m" | "M" )
					cardinality="m"
					break
				;;
				* )
					echo "{VTred}ERROR:${VTnorm} invalid response, try again"
					continue
				;;
			esac
		else
			cardinality="s"
			break
		fi
	done
fi

lxr_root=`pwd`
echo
echo "Your LXR root directory is: ${VTbold}${lxr_root}${VTnorm}"
echo
# Escape the path separator (also regexp delimitor)
lxr_root="${lxr_root//\//\\/}"

if [ "$everything" == 1 ] ; then

	chmod -R +rx templates
	chmod 555 templates
	echo "templates directory now protected read-only"

	target=".htaccess"
	cp templates/Apache/htaccess-generic ${target}
	chmod u=rwx ${target}
	echo "File ${VTbold}${target}${VTnorm} written in your LXR root directory"
	echo "--- List its content with 'more $target'"

	target="apache2-require.pl"
	sed -e "s/%LXRroot%/${lxr_root}/g" templates/Apache/$target > $confdir/$target
	echo "File ${VTbold}$target${VTnorm} written in $confdir directory"

	target="apache-lxrserver.conf"
	sed -e "s/%LXRroot%/${lxr_root}/g" \
		-e "s/#=$cardinality=//" \
		templates/Apache/$target > $confdir/$target
	echo "File ${VTbold}${target}${VTnorm} written in $confdir directory"

	target="lighttpd-lxrserver.conf"
	sed -e "s/%LXRroot%/${lxr_root}/g" templates/lighttpd/$target \
		> $confdir/lighttp-lxrserver.conf
	echo "File ${VTbold}${target}${VTnorm} written in $confdir directory"
	if [ "$cardinality" == "m" ] ; then
		echo "${VTyellow}You need to manually configure ${VTnorm}${VTbold}$target ${VTyellow}for multiple trees operation${VTnorm}"
	fi

	chmod u=rwx,go=rx ${confdir}/*

fi

# lxr.conf pre-configuration

lc="${confdir}/${lxt}"		# lxr.conf destination
cp templates/${lxt} $lc
chmod u=rwx ${lc}

sed -e "s/%LXRroot%/${lxr_root}/g" -i $lc

glimpse=`which glimpse 2>/dev/null`
if [[ "$glimpse" ]] ; then	# glimpse exists
	glimpse="${glimpse//\//\\/}"
	sed -e "s/%glimpse%/$glimpse/" -i $lc
	glimpseindex=`which glimpseindex`
	if [[ "$glimpseindex" ]] ; then
		glimpseindex="${glimpseindex//\//\\/}"
		sed -e "s/%glimpseindex%/${glimpseindex}/" -i $lc
	else
		echo "${VTred}***Error:${VTnorm} glimpseindex not installed with glimpse!"
	fi
else						# no glimpse
	sed -e "/%glimpse%/s/^/#/" \
	    -e "/%glimpseindex%/s/^/#/" \
		-i $lc
fi

swish=`which swish-e 2>/dev/null`
if [[ "$swhish" ]] ; then		# swish-e exists
	swish="${swish//\//\\/}"
	sed -e "s/%swish%/${swish}/" -i $lc
else						# no swhish-e
	sed -e '/%swish%/s/^/#/' -i $lc
fi

if [[ (-z "$glimpse") && (-z "$swish") ]] ; then
	echo "${VTred}***Error:${VTnorm} neither glimpse nor swish-e installed!"
fi

if [[ "$glimpse" && "$swish" ]] ; then
	echo "${VTred}***Error:${VTnorm} both glimpse and swish-e installed!"
	echo "*** Manually edit lxr.conf to comment out one of them ***"
fi

ctagsbin=`which ctags`
if [[ "$ctagsbin" ]] ; then		# ctags exists
	ctagsbin="${ctagsbin//\//\\/}"
	sed -e "s/%ctags%/${ctagsbin}/" -i $lc
else						# no swhish-e
	echo "${VTred}***Error:${VTnorm} ctags not installed!"
fi

echo "Prototype ${VTbold}${lxt}${VTnorm} written in $confdir directory"

echo
echo "${VTyellow}***${VTnorm} Configuration directory $confdir now contains: ${VTyellow}***${VTnorm}"
ls -al $confdir

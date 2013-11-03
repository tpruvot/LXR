#!/bin/bash
# $Id: kernel-vars-grab.sh,v 1.1 2012/09/22 09:01:48 ajlittoz Exp $

shopt -s extglob
. ${0%%+([^/])}ANSI-escape.sh

#	Strip directory from command
cmdname=${0##*/}

confdir="custom.d"

#	Decode options and arguments
verbose=0
erase=0
suffix="_list.txt"
kvd=
while [[ $# > 0 ]] ; do
	case "$1" in
		--help | -h )
			echo "$cmdname [OPTION]... kernel-versions-dir/"
			echo "Creates in ${confdir} files containing lists of Linux kernel architectures"
			echo "and sub-architectures suitable for reading by readfile() in variables 'range'"
			echo "attribute"
			echo
			echo "OPTION:"
			echo "  -h, --help     print this reminder and stop"
			echo "  -v, --verbose  monitor what's happening"
			echo "  -z, --erase    erase all files with given or default --suffix"
			echo "                 (if -z not specified, merge results in files)"
			echo "      --suffix=s suffix for list files (default ${suffix})"
			echo
			echo "kernel-versions-dir/ directory containing one version of kernel source"
			echo "                     per sub-directory"
			exit 0
		;;
		--suffix=* )
			suffix="${1#--suffix=}"
			if [ "x$suffix" == "x" ] ; then
				echo "${VTred}${cmdname}: void suffix is not allowed!${VTnorm}"
				exit 1
			fi
		;;
		--verbose | -v )
			verbose=1
		;;
		--erase | -z )
			erase=1
		;;
		--[^-]* | -[^-]* )
			echo "${VTyellow}${cmdname}:${VTnorm} unknown option $1"
		;;
		* )
			kvd="$1"
		;;
	esac
	shift
done

if [[ ! -d "scripts" || ! -d "${confdir}" || ! -d "templates" ]] ; then
	echo "${VTred}${cmdname}: current working directory not LXR's!${VTnorm}"
	exit 1
fi


if [ "x$kvd" == "x" ] ; then
	echo "${VTred}${cmdname}: no kernel directory!${VTnorm}"
	exit 1
fi

#	Ensure trailing slash present
kvd=${kvd%/}/

if [ $verbose == 1 ] ; then
	echo "${VTyellow}***${VTnorm} Kernel architecture variants enumeration for LXR (\$Revision: 1.1 $) ${VTyellow}***${VTnorm}"
	echo "Kernel directory: $kvd"
fi

if [ ! -d "$kvd" ] ; then
	echo "${VTred}${cmdname}: $kvd does not exist!${VTnorm}"
	exit 1
fi

#	Build version list
vlist=`ls -FL1 $kvd | grep "/$"`

if [ "x$vlist" == "x" ] ; then
	echo "${VTred}${cmdname}: $kvd does not contain sub-directories!${VTnorm}"
	exit 1
fi

collect_sub_arch () {
	v=$1
	a=$2
	target=$3
	ls -FL1 ${kvd}${v}arch/${a} \
	| grep "^${target}-.*/$" \
	| sed -e "s/^${target}-//" -e "s|/$||" \
	>> ${confdir}/${a}_${target}${suffix}
}

scan_one_version () {
	if [ $verbose == 1 ] ; then
		echo "--- Checking $1"
	fi
	if [[ ! -d "${kvd}${1}kernel" || ! -d "${kvd}${1}include" || ! -d "${kvd}${1}arch" ]] ; then
		echo "${VTyellow}$1 does not look like a kernel directory -- skipped!${VTnorm}"
		return
	fi
	seen_one_version=1
	echo "${1%/}" >> ${confdir}/version${suffix}
	if [ $verbose == 1 ] ; then
		echo "--- Scanning $1"
	fi
	#	Enumerate architectures
	target="arch"
	ls -FL1 ${kvd}${1}${target} \
	| grep "/$" \
	| sed -e "s|/$||" \
	>> ${confdir}/${target}${suffix}
	#	Manage sub-architectures
	for a in arm avr32 blackfin ; do
		collect_sub_arch "$1" $a "mach"
	done
	collect_sub_arch "$1" "arm" "plat"
	collect_sub_arch "$1" "cris" "arch"
	collect_sub_arch "$1" "mn10300" "proc"
	collect_sub_arch "$1" "mn10300" "unit"
	collect_sub_arch "$1" "um" "sys"
}

if [ $erase == 1 ] ; then
	if [ $verbose == 1 ] ; then
		echo
		echo "${VTyellow}***${VTnorm} Erasing files:"
		ls ${confdir}/*${suffix}
	fi
#	rm -f ${confdir}/*${suffix}
fi

if [ $verbose == 1 ] ; then
	echo
	echo "${VTyellow}***${VTnorm} Scanning sub-directories"
fi
seen_one_version=0
for d in $vlist ; do
	scan_one_version $d
done
if [ $seen_one_version == 0 ] ; then
	echo "${VTred}$cmdname: no kernel version found!${VTnorm}"
	exit 1
fi

if [ $verbose == 1 ] ; then
	echo
	echo "${VTyellow}***${VTnorm} Sorting and pruning list files"
fi
for l in ${confdir}/*${suffix}; do
	sort -fu $l -o ${confdir}/%%SORT%%OUTPUT%%
	mv -f ${confdir}/%%SORT%%OUTPUT%% $l
done

if [ $verbose == 1 ] ; then
	echo "${VTgreen}***${VTnorm} Done $SECONDS seconds"
fi

#!/bin/sh
# $Id: initdb-config.sh,v 1.4 2012/02/04 13:39:56 ajlittoz Exp $

echo "*** initdb script configurator for LXR (\$Revision: 1.4 $) ***"
echo ""
echo "      In case you make a mistake, you can cancel the"
echo "      whole process by typing ctl-C."
echo ""

while : ; do
	read -p "Which is your database engine? [MYSQL/oracle/postgres] " dbengine
	if [ "$dbengine" ] ; then
		case "$dbengine" in
			"mysql" | "MYSQL" )
				dbengine="mysql"
				break
			;;
			"oracle" | "ORACLE" )
				dbengine="oracle"
				break
			;;
			"postgres" | "POSTGRES" )
				dbengine="postgres"
				break
			;;
			* )
				echo "ERROR: invalid response, try again"
				continue
			;;
		esac
	else
		dbengine="mysql"
		break
	fi
done

template="templates/initdb/initdb-${dbengine}-template.sql"
outscript="lxrconf.d/initdb-${dbengine}-custom.sql"

if [ "$dbengine" != "oracle" ] ; then
	read -p "Which is your database name? [lxr] " dbname
	if [ ! "$dbname" ] ; then
		dbname="lxr"
	fi
fi

read -p "Which table prefix will you use? [lxr_] " dbprefix
if [ ! "$dbprefix" ] ; then
	dbprefix="lxr_"
fi

if [ "$dbengine" != "oracle" ] ; then
	read -p "Under which user name will you connect to the database? [lxr] " dbuser
	if [ ! "$dbuser" ] ; then
		dbuser="lxr"
	fi
fi

read -p "Output script name? [$outscript] " answer
if [ "$answer" ] ; then
	outscript=$answer
fi

echo ""
echo "     Your database engine is      $dbengine"
if [ "$dbengine" != "oracle" ] ; then
echo "     Your database is             $dbname"
fi
echo "     The tables are prefixed with $dbprefix"
if [ "$dbengine" != "oracle" ] ; then
echo "     You connect as               $dbuser"
fi
echo "     Configuration script in      $outscript"
echo ""

while : ; do
	read -p "Is this correct? [YES|no] " answer
	if [ "$answer" ] ; then
		case "$answer" in
			"y" | "Y" | "yes")
				answer=1
				break
			;;
			"n" | "N" | "no")
				answer=0
				break
			;;
			*)
				echo "ERROR: Invalid response, expected yes or no."
				continue
			;;
		esac
	else
		answer=1
		break
	fi
done

if [ $answer -ne 1 ] ; then
	exit 1
fi

sed -e "s/%DB_tbl_prefix%/$dbprefix/g" $template \
	| sed -e "s/%DB_name%/$dbname/g" \
	| sed -e "s/%DB_user%/$dbuser/g" >> "$outscript"

echo ""
echo "Init script saved in $outscript"

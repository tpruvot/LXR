#!/bin/bash
# $Id: ANSI-escape.sh,v 1.1 2012/04/02 19:01:35 ajlittoz Exp $

# ANSI escape sequences

CSI=$'\x1b[';	# CSI = esc [
VTbold="${CSI}1m";
VTnorm="${CSI}0m";
VTred="${VTbold}${CSI}31m";
VTyellow="${VTbold}${CSI}33m";
VTgreen="${VTbold}${CSI}32m";

#########################################################################
# Makefile for project inactiveholds2.0
# Created: 2019-01-29
# Copyright (c) Edmonton Public Library 2019
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
#<one line to give the program's name and a brief idea of what it does.>
#    Copyright (C) 2019  Andrew Nisbet, Edmonton Public Library
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
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
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
#      0.0 - Dev.
#########################################################################
SERVER=its@epl-el1.epl.ca
REMOTE=/home/its/InactiveHolds
LOCAL=~/projects/inactiveholds2.0
APP=inactiveholds2.0.sh
RPT_A=rpt118942.sh
.PHONY: test run
reports:
	scp ${LOCAL}/${RPT_A} ${SERVER}:${REMOTE}/Reports/118942
install: 
	scp ${LOCAL}/${APP} ${SERVER}:${REMOTE}



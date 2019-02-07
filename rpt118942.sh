#!/bin/bash
###############################################################################
#
# Bash shell script for reporting inactive holds as per ticket 118942. See below.
#
# Capture information about items before they are purged from the ILS.
#
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
###############################################################################
TICKET=118942
WORKING_DIR=/home/its/InactiveHolds/Reports/$TICKET
DBASE_DIR=/home/its/InactiveHolds
VERSION="1.0"  # Tested.
DATABASE=inactive_holds.db
DBASE=$DBASE_DIR/$DATABASE
PIPE=/home/its/bin/pipe.pl
START_DATE=20180101   # See -d for setting the start date of the report.
END_DATE=20181231     # See -d for more information.
IH_REPORT=$WORKING_DIR/$TICKET.inactive.holds.csv
CKOS_REPORT=$WORKING_DIR/$TICKET.checkouts.csv
ADDRESSES="andrew.nisbet@epl.ca"

########## Functions ###############
# Hi Andrew,
# Could you please help me out with the question we got from Pilar – can we determine the number of 
# holds for 2018 and then go all the way back to 2014?
# (see also the initial email below from 2014)
# - is it something we can pull from ILS or can probably do it through BCA.
#
# Thank you kindly,
# Mihaela
# From: Tina Thomas <Tina.Thomas@EPL.CA> 
# Sent: Tuesday, February 05, 2019 2:26 PM
# To: Mihaela Voicu <Mihaela.Voicu@EPL.CA>
# Subject: FW: Checkouts from Holds 2013_2014
#
# See below
# We have had stats in the past around the % of our checkouts that come from holds. Pilar is only asking for 2018. Can we get? Would it also be possible to fill in the data so we have the full year 2014, 2015, 2016, 17 and 18?
# Thanks
# Tina
#
               # TINA THOMAS
               # EXECUTIVE DIRECTOR, STRATEGY AND INNOVATION
               # T: 780.496.7046   F: 780.496.7097   C: 780.996.0818
               # tina.thomas@epl.ca
#
# From: Pilar Martinez 
# Sent: Friday, January 18, 2019 10:38 AM
# To: Tina Thomas <Tina.Thomas@EPL.CA>
# Subject: FW: Checkouts from Holds 2013_2014
#
# Hi Tina,
#
# I am hoping PAR/IT can provide figures for 2018.  Is this possible?
#
# Pilar
#
                  # PILAR MARTINEZ
                  # CHIEF EXECUTIVE OFFICER
                  # T: 780.496.7050   F: 780.496.7097   C: 780.886.4547
                  # pilar.martinez@epl.ca
#
# From: Pam Ryan 
# Sent: Monday, August 11, 2014 11:54 AM
# To: Library Services Leadership Team <TeamSponsors@epl.ca>
# Subject: Checkouts from Holds 2013_2014
#
# Hi all,
#
# We’ve been saying that ~20% of our checkouts are via Holds but it was time to see
# where this actually sits. The attached checkouts from Holds table that Lachlan 
# pulled includes data for our largest physical collections. Total copies, 
# total checkouts and turnover rates are provided for comparison too.
#
# Some quick highlights:
# *	The average across all item types is 25% (2013) and 26% (2014 YTD) of checkouts 
# through Holds meaning the majority of checkouts are still through what customers find in-branch for most item types
# *	As expected, there is a difference between Adult/JUV Holds checkout rates, 
# with Adult books seeing 45% of checkouts through Holds
# *	Other language materials are good candidates for a pilot to direct 
# floating / swapping of materials between branches to freshen local collections because Holds are so low
#
# Pam
#
                # PAM RYAN
                # DIRECTOR, COLLECTIONS & TECHNOLOGY
                # T: 780.442.6280   F: 780.496.8317   C: 780.668.2205
                # pryan@epl.ca
                
# Prints the usage message to stdout then exits with status 1.
# param:  none
usage()
{
    cat << EOFU!
 Usage: $0 
 Creates a report of inactive holds as per the specifications derived from emails
 that originated from Pam Ryan in 2014
 
Flags:
 -d{yyyymmdd,yyyymmdd}: Date range of the query. Dates are inclusive and must be in the format of 'yyyymmdd'
     separated by a ',' - comma.
 -x: This help message.
 
==snip==
We’ve been saying that ~20% of our checkouts are via Holds but it was time to see where this actually sits. The attached checkouts from Holds table that Lachlan pulled includes data for our largest physical collections. Total copies, total checkouts and turnover rates are provided for comparison too.

Some quick highlights:
*	The average across all item types is 25% (2013) and 26% (2014 YTD) of checkouts through Holds meaning the majority of checkouts are still through what customers find in-branch for most item types
*	As expected, there is a difference between Adult/JUV Holds checkout rates, with Adult books seeing 45% of checkouts through Holds
*	Other language materials are good candidates for a pilot to direct floating / swapping of materials between branches to freshen local collections because Holds are so low

Pam
==snip==


 version $VERSION
EOFU!
    exit 1
}

# Asks if user would like to do what the message says.
# param:  message string.
# return: 0 if the ANSWER was yes and 1 otherwise.
confirm()
{
	if [ -z "$1" ]; then
		printf "** error, confirm_yes requires a message.\n" >&2
		exit 1
	fi
	local message="$1"
	printf "%s? y/[n]: " "$message" >&2
	read a
	case "$a" in
		[yY])
			if [ "$VERBOSE" != 1 ]; then
				printf "yes selected.\n" >&2
			fi
			echo 0
			;;
		*)
			if [ "$VERBOSE" != 1 ]; then
				printf "no selected.\n" >&2
			fi
			echo 1
			;;
	esac
}

# sqlite> .schema
# CREATE TABLE inactive_holds (
    # PickupLibrary CHAR(6) NOT NULL,
    # InactiveReason CHAR(20) NOT NULL,
    # DateInactive INTEGER,
    # DateHoldPlaced INTEGER,
    # HoldType CHAR(2),
    # Override CHAR(2),
    # NumberOfPickupNotices INTEGER,
    # DateNotified INTEGER,
    # DateAvailable INTEGER,
    # ItemType CHAR(20)
# );
# CREATE INDEX idx_inactive_holds_pickup ON inactive_holds (PickupLibrary);
# CREATE INDEX idx_inactive_holds_reason ON inactive_holds (InactiveReason);
# CREATE INDEX idx_inactive_holds_itype ON inactive_holds (ItemType);
# CREATE INDEX idx_inactive_holds_htype ON inactive_holds (HoldType);
# CREATE INDEX idx_inactive_holds_date_inactive ON inactive_holds (DateInactive);
# CREATE INDEX idx_inactive_holds_date_available ON inactive_holds (DateAvailable);
# CREATE INDEX idx_inactive_holds_branch_date_inactive ON inactive_holds (PickupLibrary, DateInactive);
# Creates inactive holds by branch for the given date range.
# param:  start date (yyyymmdd) inclusive.
# param:  end date (yyyymmdd) inclusive.
rpt_inactive_holds_by_branch()
{
    local start=$1
    local end=$2
    local start_date=$(echo $start | $PIPE -mc0:####-##-#)
    local end_date=$(echo $end | $PIPE -mc0:####-##-#)
    echo "collecting inactive hold data..." >&2
    local sql="SELECT PickupLibrary,InactiveReason,ItemType,count(ItemType) FROM inactive_holds WHERE DateInactive>=$start AND DateInactive<=$end GROUP BY PickupLibrary,InactiveReason,ItemType ORDER BY PickupLibrary;"
    echo ${sql} | sqlite3 $DBASE >$TICKET.rpt
    if [ ! -e "$TICKET.rpt" ]; then
        echo "report failed to produce results" >&2
        exit 1
    fi
    cat $TICKET.rpt | $PIPE -TCSV:"Branch,Inactive reason,Item type,Count,$start_date,$end_date" >$IH_REPORT
        if [ ! -e "$IH_REPORT" ]; then
        echo "$0 failed to produce csv output in "`pwd`"." | mailx -s"** Report $TICKET failed." -a"From: its@epl-el1.epl.ca" "$ADDRESSES"
        exit 1
    fi
    echo "Inactive holds report results are attached." | mailx -s"Report for ticket $TICKET results" -a"From: its@epl-el1.epl.ca" -A $IH_REPORT "$ADDRESSES"
    echo "done." >&2
    echo "collecting checkout data from production..." >&2
    # To get the comparison data from Quad of total checkouts:
    # SELECT Branch,Type,count(ItemId) FROM ckos INNER JOIN item ON ItemId=Id WHERE Date>=$start000000 AND Date<=$end000000 GROUP BY Branch,Type ORDER BY Branch;
    local sql_production="SELECT Branch,Type,count(ItemId) FROM ckos INNER JOIN item ON ItemId=Id WHERE Date>=${start}000000 AND Date<=${end}000000 GROUP BY Branch,Type ORDER BY Branch;"
    ssh -C sirsi@eplapp.library.ualberta.ca "echo \"$sql_production\" | /bin/sqlite3 /s/sirsi/Unicorn/EPLwork/cronjobscripts/Quad/quad.db" >$TICKET.prod.rpt
    if [ ! -e "$TICKET.prod.rpt" ]; then
        echo "report on production failed to produce results" >&2
        exit 1
    fi
    cat $TICKET.prod.rpt | $PIPE -TCSV:"Branch,Item type,Count,$start_date,$end_date" >$CKOS_REPORT
        if [ ! -e "$CKOS_REPORT" ]; then
        echo "$0 failed to produce csv output in "`pwd`"." | mailx -s"** Report of checkouts for ticket $TICKET failed." -a"From: its@epl-el1.epl.ca" "$ADDRESSES"
        exit 1
    fi
    echo "Checkout report from EPLAPP are attached." | mailx -s"Report for ticket $TICKET results" -a"From: its@epl-el1.epl.ca" -A $CKOS_REPORT "$ADDRESSES"
    echo "done." >&2
}

########## Application ###############
# Argument processing.
while getopts ":d:rx" opt; do
  case $opt in
    d)	echo "-d report triggered with params $OPTARG." >&2
        START_DATE=$(echo $OPTARG | $PIPE -W, -oc0 -tc0)
        END_DATE=$(echo $OPTARG | $PIPE -W, -oc1 -tc1)
        echo "\$START_DATE set to $START_DATE" >&2
        echo "\$END_DATE set to $END_DATE" >&2
        ;;
    ### Run report.
    r)	echo "-r report triggered." >&2
        echo "preparing SQL" >&2
        
        echo "done" >&2
        ;;
    x)	usage
        ;;
  esac
done
# Run report(s)
rpt_inactive_holds_by_branch $START_DATE $END_DATE 
# EOF

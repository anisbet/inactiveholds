#!/bin/bash
###########################################################################
#
# Bash shell script for project inactiveholds2.0
# Builds a database on its@epl-el1.epl.ca of inactive holds.
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
#########################################################################
SERVER=sirsi\@eplapp.library.ualberta.ca
INACTIVE_HOLDS_DIR=/s/sirsi/Unicorn/EPLwork/cronjobscripts/Inactive_holds
WORKING_DIR=/home/its/InactiveHolds
VERSION="1.0"  # Dev.
DATABASE=inactive_holds.db
BACKUP_DATA=inactive_holds.tar
INACTIVE_HOLDS_TABLE_NAME=inactive_holds
HOLD_ACTIVITY=Holds_activity_for_
DBASE=$WORKING_DIR/$DATABASE
LOG=$WORKING_DIR/inactive_holds.log
EMAILS=andrew.nisbet\@epl.ca
# Displays the usage for this product.
# param:  none
# return: none
usage()
{
    cat << EOFU!
 Usage: $0 
  Maintains a database that houses inactive holds data.

  The ILS caputures inactive holds information, but the ILS is a transactional database,
  and we need to store information for future analysis.

Flags:
  -c: Clean up log files on ILS ($SERVER:$INACTIVE_HOLDS_DIR).
  -C: Create inactive holds database ($DBASE).
  -i: Create inactive holds database table indices.
  -f: Fetch inactive logs from ILS ($SERVER:$INACTIVE_HOLDS_DIR) 
      to the data directory ($WORKING_DIR/Data).
  -l: Loads local $HOLD_ACTIVITY files from $WORKING_DIR/Data directory.
      The table indices are removed prior to loading, and replaced after
      the load is complete. Local $HOLD_ACTIVITY* files are backed up
      and local files removed but no files on the ILS are touched.
      Equivalent to restore.
  -L: Load data from data directory ($WORKING_DIR/Data).
      The script searches for 'lst' files in $WORKING_DIR/Data, loads them
      undates the backup tar ball, and cleans $WORKING_DIR/Data and if successful
      cleans up $SERVER:$INACTIVE_HOLDS_DIR of any '$HOLD_ACTIVITY' files.
      If the clean up activity is successful, indices are added back to the 
      table(s) in $DATABASE.
      Equivalent to -f, -l, -c, in that order.

Schema:
------- 
CREATE TABLE $INACTIVE_HOLDS_TABLE_NAME (
    PickupLibrary CHAR(6) NOT NULL,
    InactiveReason CHAR(20) NOT NULL,
    DateInactive INTEGER,
    DateHoldPlaced INTEGER,
    HoldType CHAR(2),
    Override CHAR(2),
    NumberOfPickupNotices INTEGER,
    DateNotified INTEGER,
    DateAvailable INTEGER,
    ItemType CHAR(20)
);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_pickup ON $INACTIVE_HOLDS_TABLE_NAME (PickupLibrary);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_reason ON $INACTIVE_HOLDS_TABLE_NAME (InactiveReason);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_itype ON $INACTIVE_HOLDS_TABLE_NAME (ItemType);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_htype ON $INACTIVE_HOLDS_TABLE_NAME (HoldType);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_inactive ON $INACTIVE_HOLDS_TABLE_NAME (DateInactive);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_available ON $INACTIVE_HOLDS_TABLE_NAME (DateAvailable);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_branch_date_inactive ON $INACTIVE_HOLDS_TABLE_NAME (PickupLibrary, DateInactive);

Data desired:
-------------

PickupLibrary|InactiveReason|DateInactive|DateHoldPlaced|HoldType|Override|NumberOfPickupNotices|DateNotified|DateAvailable|ItemType

Sample input
------------
# EPLCSD|FILLED|20190124|20171012|T|N|1|20190123|20190123|BOOK|
# EPLWMC|FILLED|20171229|20171013|T|N|0|0|0|CD|
# EPLZORDER|FILLED|20190125|20171104|C|Y|0|0|20190125|FLICKSTOGO|
  holds:
    PickupLibrary,
    InactiveReason,
    DateInactive,
    DateHoldPlaced,
    HoldType,
    Override,
    NumberOfPickupNotices,
    DateNotified,
    DateAvailable,
    ItemType,
    
 collected with the API:
   selhold -k"<\$TodaysDate" -l"FILLED"  -oIwlkptunm5 | selitem -iI -oSt  > Holds_activity_for_\$TodaysDate.lst
   selhold -k"<$DateNinetyDaysAgo"       -oIwlkptunm5 | selitem -iI -oSt >> Holds_activity_for_\$TodaysDate.lst
   
 Version: $VERSION
EOFU!
}

# Asks if user would like to do what the message says.
# param:  message string.
# return: 0 if the answer was yes and 1 otherwise.
confirm()
{
	if [ -z "$1" ]; then
		echo `date +"%Y-%m-%d %H:%M:%S"`" ** error, confirm_yes requires a message." >>$LOG
		echo "** error, confirm_yes requires a message." >&2
		exit 1
	fi
	local message="$1"
	echo `date +"%Y-%m-%d %H:%M:%S"`" $message? y/[n]: " >>$LOG
	echo "$message? y/[n]: " >&2
	read answer
	case "$answer" in
		[yY])
			echo `date +"%Y-%m-%d %H:%M:%S"`" yes selected." >>$LOG
			echo "yes selected." >&2
			echo 0
			;;
		*)
			echo `date +"%Y-%m-%d %H:%M:%S"`" no selected." >>$LOG
			echo "no selected." >&2
			echo 1
			;;
	esac
}

# Creates the one table for inactive holds data.
# param:  none
# return: none
create_database()
{
    ######### schema ###########
    # CREATE TABLE $INACTIVE_HOLDS_TABLE_NAME (
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
    ######### schema ###########
    # None of the data in the table individually, or collectively can be considered a primary key candidate.
    if [ -s "$DBASE" ]; then
        echo "*warn: $DBASE exists!" >&2
        ANSWER=$(confirm "create $DBASE ")
        if [ "$ANSWER" == "0" ]; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" creating new $DBASE" >>$LOG
            echo "creating new $DBASE" >&2
            rm $DBASE
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" Keeping database $DBASE. Exiting." >>$LOG
            echo "Keeping database $DBASE. Exiting." >&2
        fi
    else
        sqlite3 $DBASE <<END_SQL
CREATE TABLE $INACTIVE_HOLDS_TABLE_NAME (
    PickupLibrary CHAR(6) NOT NULL,
    InactiveReason CHAR(20) NOT NULL,
    DateInactive INTEGER,
    DateHoldPlaced INTEGER,
    HoldType CHAR(2),
    Override CHAR(2),
    NumberOfPickupNotices INTEGER,
    DateNotified INTEGER,
    DateAvailable INTEGER,
    ItemType CHAR(20)
);
END_SQL
        echo `date +"%Y-%m-%d %H:%M:%S"`" $DBASE created" >>$LOG
    fi
}

# Creates the item table indices.
# param:  none
ensure_indices()
{
    # creates indices that will be popular during queries.
    if [ -s "$DBASE" ]; then
        sqlite3 $DBASE <<END_SQL
CREATE INDEX IF NOT EXISTS idx_inactive_holds_pickup ON $INACTIVE_HOLDS_TABLE_NAME (PickupLibrary);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_reason ON $INACTIVE_HOLDS_TABLE_NAME (InactiveReason);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_itype ON $INACTIVE_HOLDS_TABLE_NAME (ItemType);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_htype ON $INACTIVE_HOLDS_TABLE_NAME (HoldType);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_inactive ON $INACTIVE_HOLDS_TABLE_NAME (DateInactive);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_available ON $INACTIVE_HOLDS_TABLE_NAME (DateAvailable);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_branch_date_inactive ON $INACTIVE_HOLDS_TABLE_NAME (PickupLibrary, DateInactive);
END_SQL
        echo `date +"%Y-%m-%d %H:%M:%S"`" indices created" >>$LOG
    else
        echo echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit 1
    fi
}

# DROP INDEX IF EXISTS from inactive holds table. This makes loading faster.
# param:  none
# return: none
drop_indices()
{
    # creates indices that will be popular during queries.
    if [ -s "$DBASE" ]; then
        sqlite3 $DBASE <<END_SQL
DROP INDEX IF EXISTS idx_inactive_holds_pickup;
DROP INDEX IF EXISTS idx_inactive_holds_reason;
DROP INDEX IF EXISTS idx_inactive_holds_itype;
DROP INDEX IF EXISTS idx_inactive_holds_htype;
DROP INDEX IF EXISTS idx_inactive_holds_date_inactive;
DROP INDEX IF EXISTS idx_inactive_holds_date_available;
DROP INDEX IF EXISTS idx_inactive_holds_branch_date_inactive;
END_SQL
        echo `date +"%Y-%m-%d %H:%M:%S"`" indices dropped." >>$LOG
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit 1
    fi
}

# Loads any '$HOLD_ACTIVITY' files in $WORKING_DIR/Data.
# param:  none
# return: none
load_inactive_holds()
{
    local failed_load_count=0
    if [ -s "$DBASE" ]; then
        for log_list in $(ls $WORKING_DIR/Data/$HOLD_ACTIVITY*); do
            cat $log_list | /home/its/bin/pipe.pl -ocontinue -m"c0:INSERT INTO inactive\_holds (PickupLibrary\,InactiveReason\,DateInactive\,DateHoldPlaced\,HoldType\,Override\,NumberOfPickupNotices\,DateNotified\,DateAvailable\,ItemType) VALUES (\"######\",c1:\"####################\",c2:#,c3:#,c4:\"##\",c5:\"##\",c6:#,c7:#,c8:#,c9:\"####################\");" -h, >$log_list.sql
            if [ -f "$log_list.sql" ]; then
                echo `date +"%Y-%m-%d %H:%M:%S"`" loading $log_list.sql..." >>$LOG
                echo "loading $log_list.sql..." >&2
                cat $log_list.sql | sqlite3 $DBASE
                rm $log_list.sql
                echo `date +"%Y-%m-%d %H:%M:%S"`" loaded successfully." >>$LOG
                echo "loaded successfully." >&2
            else
                ((failed_load_count+=1))
                echo `date +"%Y-%m-%d %H:%M:%S"`" * warn: no records to load. $log_list.sql contains no statements." >>$LOG
                echo "* warn: no records to load. $log_list.sql contains no statements." >&2
            fi
        done
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit 1
    fi
    echo $failed_load_count
}

# Backs up data in the $WORKING_DIR/Data directory, then removes the '$HOLD_ACTIVITY' files
# from $WORKING_DIR/Data, then removes the '$HOLD_ACTIVITY' files from the ILS so they 
# don't get reloaded. This is important because it is possible to load a file multiple 
# times. The reason is this data doesn't have any identifiers that can be used to make 
# a primary key for the table.
# param:  none
# return: 0 if successful, but the script will exit with status 1 if the files couldn't be
#         cleaned or a backup of the local '$HOLD_ACTIVITY' files couldn't be backed up.
cleanup()
{
    if cd $WORKING_DIR/Data; then
        echo "now in "`pwd` >&2
        if tar uvf $BACKUP_DATA $HOLD_ACTIVITY*; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" '$HOLD_ACTIVITY' files successfully backed up." >>$LOG
            echo "'$HOLD_ACTIVITY' files successfully backed up." >&2
            rm $HOLD_ACTIVITY*
            ## Uncomment below after testing.
            if ! ssh -C $SERVER "rm $INACTIVE_HOLDS_DIR/$HOLD_ACTIVITY*"; then
                echo `date +"%Y-%m-%d %H:%M:%S"`" *warning: failed to clean up '$HOLD_ACTIVITY' files from $SERVER $INACTIVE_HOLDS_DIR. Do it manually to avoid duplicate inserts of data." >>$LOG
                echo "*warn: failed to clean up '$HOLD_ACTIVITY' files from ILS." >&2
                echo "*warn: Do it manually to avoid duplicate inserts of data." >&2
                echo `date +"%Y-%m-%d %H:%M:%S"`" *warning: failed to clean up '$HOLD_ACTIVITY' files from $SERVER $INACTIVE_HOLDS_DIR. Do it manually to avoid duplicate inserts of data." | mailx -s"*warning removing inactive holds lists, chance of reloading next time!" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
                exit 1
            fi
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" ***error failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." >>$LOG
            echo "failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." >&2
            echo `date +"%Y-%m-%d %H:%M:%S"`" ***error failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." | mailx -s"*warning removing inactive holds lists, chance of reloading next time!" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
            exit 1
        fi
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" $WORKING_DIR/Data is required but not created, exiting because nothing to clean up." >>$LOG
        echo "$WORKING_DIR/Data is required but not created, exiting because nothing to clean up." >&2
        exit 1 
    fi
}

# Fetches files from the ILS, creating the Data directory if required.
# param:  none
fetch_files()
{
    if [ -d "$WORKING_DIR/Data" ]; then
        scp $SERVER:$INACTIVE_HOLDS_DIR/*.lst $WORKING_DIR/Data
    else
        ANSWER=$(confirm "create directory $WORKING_DIR/Data ")
        if [ "$ANSWER" == "0" ]; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" creating $WORKING_DIR/Data" >>$LOG
            echo "creating $WORKING_DIR/Data" >&2
            mkdir -p $WORKING_DIR/Data
            scp $SERVER:$INACTIVE_HOLDS_DIR/*.lst $WORKING_DIR/Data
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" $WORKING_DIR/Data is required but not created, exiting." >>$LOG
            echo "$WORKING_DIR/Data is required but not created, exiting." >&2
            exit 1
        fi
    fi
}

# Argument processing.
while getopts ":cCdfilLx" opt; do
  case $opt in
	c)	echo `date +"%Y-%m-%d %H:%M:%S"`" -c triggered to clean up the files on the ILS ($SERVER)." >>$LOG
        echo "-c triggered to clean up the files on the ILS ($SERVER)." >&2
        cleanup
		;;
    C)	echo `date +"%Y-%m-%d %H:%M:%S"`" -C triggered to create new database (if necessary)." >>$LOG
        echo "-C triggered to create new database (if necessary)." >&2
        create_database
		;;
    d)	echo `date +"%Y-%m-%d %H:%M:%S"`" -d triggered to drop indices from $DBASE." >>$LOG
        echo "-d triggered to drop indices from $DBASE." >&2
        drop_indices
		;;
    f)	echo `date +"%Y-%m-%d %H:%M:%S"`" -f triggered to fetch files from the ILS ($SERVER)." >>$LOG
        echo "-f triggered to fetch files from the ILS ($SERVER)." >&2
        fetch_files
		;;
    i)	echo `date +"%Y-%m-%d %H:%M:%S"`" -i triggered to rebuild indices" >>$LOG
        echo "-i triggered to rebuild indices" >&2
        ensure_indices
		;;
    l)	echo `date +"%Y-%m-%d %H:%M:%S"`" -l triggered to run data load" >>$LOG
        echo "-l triggered to run data load" >&2
        drop_indices
        # Use a special clean up that doesn't wipe files from the ILS. We may be just restoring from backup.
        if load_inactive_holds; then
            CURR_DIR=$(pwd)
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds loaded successfully." | mailx -s"Inactive holds status: success" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
            cd $WORKING_DIR/Data
            tar uvf $BACKUP_DATA $HOLD_ACTIVITY*
            echo `date +"%Y-%m-%d %H:%M:%S"`" '$HOLD_ACTIVITY' files successfully backed up." >>$LOG
            echo "'$HOLD_ACTIVITY' files successfully backed up." >&2
            rm $HOLD_ACTIVITY*
            cd $CURR_DIR  # Go back to where you were before we 'cd'd into the Data directory.
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds load failed. Check log in its@EPL-EL1:~/InactiveHolds for details. Fix before it re-runs to avoid duplicate data loads." | mailx -s"Inactive holds status: fail" -a"From:its@epl-el1.epl.ca" "$EMAILS"
        fi
        ensure_indices
		;;
    L)	echo `date +"%Y-%m-%d %H:%M:%S"`" -L triggered to fetch, drop indices, load data, clean up if successful, and replace indices." >>$LOG
        echo "-L triggered to run" >&2
        fetch_files
        drop_indices
        if load_inactive_holds; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds loaded successfully." | mailx -s"Inactive holds status: success" -a"From:its@epl-el1.epl.ca" "$EMAILS"
            cleanup
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds load failed. Check log in $SERVER $WORKING_DIR for details. Fix before it re-runs to avoid duplicate data loads. Restore from backup in $WORKING_DIR/Data if necessary." | mailx -s"Inactive holds status: fail" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
        fi
        ensure_indices
		;;
	x)	usage
		;;
  esac
done
exit 0

# EOF

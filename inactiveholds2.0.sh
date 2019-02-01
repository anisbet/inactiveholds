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
VERSION="0.2"  # Dev.
DATABASE=inactive_holds.db
BACKUP_DATA=inactive_holds.tar
INACTIVE_HOLDS_TABLE_NAME=inactive_holds
HOLD_ACTIVITY=Holds_activity_for_
DBASE=$WORKING_DIR/$DATABASE
LOG=$WORKING_DIR/inactive_holds.log

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
  -l: Load data from data directory ($WORKING_DIR/Data).
      The script searches for files then end in 'lst' to load,
      then it updates the backup tar ball. To improve load times the indices are removed
      the data is loaded, then the indices are re-added.
  -L: Fetch new logs, load data, and clean files from ILS.
      Same as -f, -l, -c, in that order.

Data desired:

-- Table design
PickupLibrary|InactiveReason|DateInactive|DateHoldPlaced|HoldType|Override|NumberOfPickupNotices|DateNotified|DateAvailable|ItemType
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

# Drops all the standard tables.
# param:  name of the table to drop.
reset_table()
{
    local table=$1
    if [ -s "$DBASE" ]; then   # If the database is not empty.
        ANSWER=$(confirm "reset table $table ")
        if [ "$ANSWER" == "1" ]; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" table will be preserved. exiting" >>$LOG
            echo "table will be preserved. exiting" >&2
            exit 1
        fi
        echo "DROP TABLE $table;" | sqlite3 $DBASE 2>/dev/null
        echo 0
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" $DBASE doesn't exist or is empty. Nothing to drop." >>$LOG
        echo "$DBASE doesn't exist or is empty. Nothing to drop." >&2
        echo 1
    fi
}

# This function builds the standard tables used for lookups. Since the underlying 
# database is a simple sqlite3 database, and there is no true date type we will be
# storing all date values as ANSI dates (YYYYMMDDHHMMSS).
# You must exend this function for each new table you wish to add.
ensure_tables()
{
    if [ -s "$DBASE" ]; then   # If the database doesn't exists and isn't empty.
        # Test table(s) so we don't create tables that exist.
        ## Inactive holds table
        if echo "SELECT COUNT(*) FROM $INACTIVE_HOLDS_TABLE_NAME;" | sqlite3 $DBASE 2>/dev/null >/dev/null; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" confirmed $INACTIVE_HOLDS_TABLE_NAME exists..." >>$LOG
            echo "confirmed $INACTIVE_HOLDS_TABLE_NAME exists..." >&2
            echo 1
        else
            create_database
            echo 0
        fi # End of creating user table.
    else
        create_database
        echo 0
    fi
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
        echo 0
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
        echo `date +"%Y-%m-%d %H:%M:%S"`" indexes added created" >>$LOG
        echo 0
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
        echo 0
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
                echo `date +"%Y-%m-%d %H:%M:%S"`" * warn: no records to load. $log_list.sql contains no statements." >>$LOG
                echo "* warn: no records to load. $log_list.sql contains no statements." >&2
            fi
        done
        echo 0
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit 1
    fi
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
            # if ! ssh $SERVER "rm $INACTIVE_HOLDS_DIR/$HOLD_ACTIVITY*"; then
                # echo `date +"%Y-%m-%d %H:%M:%S"`" *warn: failed to clean up '$HOLD_ACTIVITY' files from ILS." >>$LOG
                # echo "*warn: failed to clean up '$HOLD_ACTIVITY' files from ILS." >&2
                # echo "*warn: Do it manually to avoid duplicate inserts of data." >&2
                # echo 1
            # fi
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." >>$LOG
            echo "failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." >&2
            exit 1
        fi
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" $WORKING_DIR/Data is required but not created, exiting because nothing to clean up." >>$LOG
        echo "$WORKING_DIR/Data is required but not created, exiting because nothing to clean up." >&2
        exit 1 
    fi
    echo 0
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
	c)	echo "-c triggered to clean up the files on the ILS ($SERVER)." >>$LOG
        echo "-c triggered to clean up the files on the ILS ($SERVER)." >&2
        cleanup
		;;
    C)	echo "-C triggered to create new database (if necessary)." >>$LOG
        echo "-C triggered to create new database (if necessary)." >&2
        create_database
		;;
    d)	echo "-d triggered to drop indices from $DBASE." >>$LOG
        echo "-d triggered to drop indices from $DBASE." >&2
        drop_indices
		;;
    f)	echo "-f triggered to fetch files from the ILS ($SERVER)." >>$LOG
        echo "-f triggered to fetch files from the ILS ($SERVER)." >&2
        fetch_files
		;;
    i)	echo "-i triggered to rebuild indices" >>$LOG
        echo "-i triggered to rebuild indices" >&2
        ensure_indices
		;;
    l)	echo "-l triggered to run data load" >>$LOG
        echo "-l triggered to run data load" >&2
        drop_indices
        load_inactive_holds
        ensure_indices
		;;
    L)	echo "-L triggered to run" >>$LOG
        echo "-L triggered to run" >&2
        fetch_files
        drop_indices
        load_inactive_holds
        ensure_indices
        cleanup
		;;
	x)	usage
		;;
  esac
done
exit 0

# EOF

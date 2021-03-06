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
VERSION="3.1.2"  # Remove exit status variable.
DATABASE=inactive_holds.db
LOG=$WORKING_DIR/inactive_holds.log
#### Test version.
# DATABASE=inactive_holds.test.db
# LOG=$WORKING_DIR/inactive_holds.test.log
#### Test version.
BACKUP_DATA=inactive_holds.tar
INACTIVE_HOLDS_TABLE_NAME=inactive_holds
HOLD_ACTIVITY=Holds_activity_for_
DBASE=$WORKING_DIR/$DATABASE
EMAILS=andrew.nisbet\@epl.ca
TRUE=0
FALSE=1
MILESTONE=''
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
  -p{YYYYMMDD}: Purge data from before this milestone date. Delete <= date inserted.

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
    ItemType CHAR(20),
    DateInserted INTEGER NOT NULL,
    Id INTEGER NOT NULL,
    PRIMARY KEY (DateInserted, Id)
);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_pickup ON $INACTIVE_HOLDS_TABLE_NAME (PickupLibrary);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_reason ON $INACTIVE_HOLDS_TABLE_NAME (InactiveReason);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_itype ON $INACTIVE_HOLDS_TABLE_NAME (ItemType);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_htype ON $INACTIVE_HOLDS_TABLE_NAME (HoldType);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_inactive ON $INACTIVE_HOLDS_TABLE_NAME (DateInactive);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_available ON $INACTIVE_HOLDS_TABLE_NAME (DateAvailable);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_branch_date_inactive ON $INACTIVE_HOLDS_TABLE_NAME (PickupLibrary, DateInactive);
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_inserted_id ON $INACTIVE_HOLDS_TABLE_NAME (DateInserted, Id);

Data desired:
-------------

PickupLibrary|InactiveReason|DateInactive|DateHoldPlaced|HoldType|Override|NumberOfPickupNotices|DateNotified|DateAvailable|ItemType|DateInserted|Id

Sample input
------------
# EPLCSD|FILLED|20190124|20171012|T|N|1|20190123|20190123|BOOK||20190129|1
# EPLWMC|FILLED|20171229|20171013|T|N|0|0|0|CD||20190129|2
# EPLZORDER|FILLED|20190125|20171104|C|Y|0|0|20190125|FLICKSTOGO||20190129|3
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
    DateInserted,
    Id,
    Primary key on (DateInserted, Id)
    
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
		exit $FALSE
	fi
	local message="$1"
	echo `date +"%Y-%m-%d %H:%M:%S"`" $message? y/[n]: " >>$LOG
	echo "$message? y/[n]: " >&2
	read answer
	case "$answer" in
		[yY])
			echo `date +"%Y-%m-%d %H:%M:%S"`" yes selected." >>$LOG
			echo "yes selected." >&2
			echo $TRUE
			;;
		*)
			echo `date +"%Y-%m-%d %H:%M:%S"`" no selected." >>$LOG
			echo "no selected." >&2
			echo $FALSE
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
    # ItemType CHAR(20),
    # DateInserted INTEGER NOT NULL,
    # Id INTEGER NOT NULL,
    # PRIMARY KEY (DateInserted, Id)
    # );
    ######### schema ###########
    # None of the data in the table individually, or collectively can be considered a primary key candidate.
    if [ -s "$DBASE" ]; then
        echo "*warn: $DBASE exists!" >&2
        ANSWER=$(confirm "create $DBASE ")
        if [ "$ANSWER" == "$TRUE" ]; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" creating new $DBASE" >>$LOG
            echo "creating new $DBASE" >&2
            rm $DBASE
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" Keeping database $DBASE. Exiting." >>$LOG
            echo "Keeping database $DBASE. Exiting." >&2
            exit $TRUE
        fi
    fi
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
    ItemType CHAR(20),
    DateInserted INTEGER NOT NULL,
    Id INTEGER NOT NULL,
    PRIMARY KEY (DateInserted, Id)
);
END_SQL
    echo `date +"%Y-%m-%d %H:%M:%S"`" $DBASE created" >>$LOG
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
CREATE INDEX IF NOT EXISTS idx_inactive_holds_date_inserted_id ON $INACTIVE_HOLDS_TABLE_NAME (DateInserted, Id);
END_SQL
        echo `date +"%Y-%m-%d %H:%M:%S"`" indices created" >>$LOG
    else
        echo echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit $FALSE
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
DROP INDEX IF EXISTS idx_inactive_holds_date_inserted_id;
END_SQL
        echo `date +"%Y-%m-%d %H:%M:%S"`" indices dropped." >>$LOG
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit $FALSE
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
            ## Produces '20150821' as the insert date from the file name.
            local insert_date=$(echo $log_list | /home/its/bin/pipe.pl -W'/' -olast | /home/its/bin/pipe.pl -Sc0:19-27) 
            ## Add the primary key for the database which is the last 2 fields; the insert date, and 
            ## an auto-increment field.
            cat $log_list | /home/its/bin/pipe.pl -mc9:"####################\|${insert_date}_" -2"c11:1,100000000" >$log_list.converted
            cat $log_list.converted | /home/its/bin/pipe.pl -ocontinue -m"c0:INSERT OR IGNORE INTO inactive\_holds (PickupLibrary\,InactiveReason\,DateInactive\,DateHoldPlaced\,HoldType\,Override\,NumberOfPickupNotices\,DateNotified\,DateAvailable\,ItemType\,DateInserted\,Id) VALUES (\"######\",c1:\"####################\",c2:#,c3:#,c4:\"##\",c5:\"##\",c6:#,c7:#,c8:#,c9:\"####################\",c10:#,c11:##########);" -h, -C"num_cols:width12-12" -TCHUNKED:"BEGIN=BEGIN TRANSACTION;,SKIP=10000.END TRANSACTION;BEGIN TRANSACTION;,END=END TRANSACTION;" >$log_list.sql
            if [ -f "$log_list.sql" ]; then
                echo `date +"%Y-%m-%d %H:%M:%S"`" loading $log_list.sql..." >>$LOG
                echo "loading $log_list.sql..." >&2
                if sqlite3 $DBASE < $log_list.sql; then
                    rm $log_list.sql
                    rm $log_list.converted
                    echo `date +"%Y-%m-%d %H:%M:%S"`" loaded successfully." >>$LOG
                    echo "loaded successfully." >&2
                else
                    echo `date +"%Y-%m-%d %H:%M:%S"`" failed to load file $log_list.sql. Fix and reload which is safe since entries are loaded with INSERT OR IGNORE." >>$LOG
                    echo " failed to load file $log_list.sql. Fix and reload which is safe since entries are loaded with INSERT OR IGNORE." >&2
                    ((failed_load_count+=1))
                fi
            else
                ((failed_load_count+=1))
                echo `date +"%Y-%m-%d %H:%M:%S"`" * warn: no records to load. $log_list.sql contains no statements." >>$LOG
                echo "* warn: no records to load. $log_list.sql contains no statements." >&2
            fi
        done
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" **error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >>$LOG
        echo "**error: $DBASE doesn't exist or is empty. Use -C to create it then -l to load data from backup." >&2
        exit $FALSE
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
            if ! ssh -C $SERVER "rm $INACTIVE_HOLDS_DIR/$HOLD_ACTIVITY*"; then
                echo `date +"%Y-%m-%d %H:%M:%S"`" *warning: failed to clean up '$HOLD_ACTIVITY' files from $SERVER $INACTIVE_HOLDS_DIR. Do it manually to avoid duplicate inserts of data." >>$LOG
                echo "*warn: failed to clean up '$HOLD_ACTIVITY' files from ILS." >&2
                echo "*warn: Do it manually to avoid duplicate inserts of data." >&2
                echo `date +"%Y-%m-%d %H:%M:%S"`" *warning: failed to clean up '$HOLD_ACTIVITY' files from $SERVER $INACTIVE_HOLDS_DIR. Do it manually to avoid duplicate inserts of data." | mailx -s"*warning succeeded in loading inactive holds, but failed to remove lists from ILS!" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
                exit $FALSE
            fi
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" ***error failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." >>$LOG
            echo "failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." >&2
            echo `date +"%Y-%m-%d %H:%M:%S"`" ***error failed to backup '$HOLD_ACTIVITY' files. Not cleaning the ILS either." | mailx -s"*warning removing inactive holds lists, chance of reloading next time!" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
            exit $FALSE
        fi
    else
        echo `date +"%Y-%m-%d %H:%M:%S"`" $WORKING_DIR/Data is required but not created, exiting because nothing to clean up." >>$LOG
        echo "$WORKING_DIR/Data is required but not created, exiting because nothing to clean up." >&2
        exit $FALSE 
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
        if [ "$ANSWER" == "$TRUE" ]; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" creating $WORKING_DIR/Data" >>$LOG
            echo "creating $WORKING_DIR/Data" >&2
            mkdir -p $WORKING_DIR/Data
            scp $SERVER:$INACTIVE_HOLDS_DIR/*.lst $WORKING_DIR/Data
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" $WORKING_DIR/Data is required but not created, exiting." >>$LOG
            echo "$WORKING_DIR/Data is required but not created, exiting." >&2
            exit $FALSE
        fi
    fi
}

# Argument processing.
while getopts ":cCdfilLp:x" opt; do
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
        success=load_inactive_holds
        if $success; then
            CURR_DIR=$(pwd)
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds loaded successfully." | mailx -s"Inactive holds status: success" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
            cd $WORKING_DIR/Data
            tar uvf $BACKUP_DATA $HOLD_ACTIVITY*
            echo `date +"%Y-%m-%d %H:%M:%S"`" '$HOLD_ACTIVITY' files successfully backed up." >>$LOG
            echo "'$HOLD_ACTIVITY' files successfully backed up." >&2
            #### Warning: don't use the cleanup() function because it zero's out files on the ILS
            #### Warning: and this is for loading or re-loading local, and backup $HOLD_ACTIVITY* files.
            rm $HOLD_ACTIVITY*
            cd $CURR_DIR  # Go back to where you were before we 'cd'd into the Data directory.
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds load failed. $success files failed to load. Check log in its@EPL-EL1:~/InactiveHolds for details. Files can be reloaded since inserts are made with INSERT OR IGNORE." | mailx -s"Inactive holds status: fail" -a"From:its@epl-el1.epl.ca" "$EMAILS"
        fi
        ensure_indices
		;;
    L)	echo `date +"%Y-%m-%d %H:%M:%S"`" -L triggered to fetch, drop indices, load data, clean up if successful, and replace indices." >>$LOG
        echo "-L triggered to run" >&2
        fetch_files
        drop_indices
        success=load_inactive_holds
        if $success; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds loaded successfully." | mailx -s"Inactive holds status: success" -a"From:its@epl-el1.epl.ca" "$EMAILS"
            cleanup
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" Inactive holds load failed. $success files failed to load. Check log in its@EPL-EL1:~/InactiveHolds for details. Files can be reloaded since inserts are made with INSERT OR IGNORE." | mailx -s"Inactive holds status: fail" -a"From:its@epl-el1.epl.ca"  "$EMAILS"
        fi
        ensure_indices
		;;
    p)  echo `date +"%Y-%m-%d %H:%M:%S"`" -p triggered to purge data from before $OPTARG." >>$LOG
        echo "-p triggered to purge data from before $OPTARG" >&2
        # This line will produce no output if the input string is not 8 digits.
        MILESTONE=$(echo $OPTARG | /home/its/bin/pipe.pl -ec0:normal_D | /home/its/bin/pipe.pl -Cc0:width8-8)
        if [[ -z "$MILESTONE" ]]; then
            echo "**error in date. Expected a string of all digits in the form of 'YYYYMMDD'." >>$LOG
            echo "**error in date. Expected a string of all digits in the form of 'YYYYMMDD'." >&2
            exit $FALSE
        fi
        # Warn of the impending purge.
        ANSWER=$(confirm "Remove data from before $MILESTONE ")
        if [ "$ANSWER" == "$TRUE" ]; then
            echo `date +"%Y-%m-%d %H:%M:%S"`" backing up data that will be removed." >>$LOG
            echo "backing up data that will be removed." >&2
            # Make a list for backup.
            echo "SELECT * FROM $INACTIVE_HOLDS_TABLE_NAME WHERE DateInserted <= '$MILESTONE';" | sqlite3 $DBASE >$WORKING_DIR/remove_$MILESTONE.bak
            if [ -s $WORKING_DIR/remove_$MILESTONE.bak ]; then
                RECORDS=$(cat $WORKING_DIR/remove_$MILESTONE.bak | wc -l)
                echo "DELETE FROM $INACTIVE_HOLDS_TABLE_NAME WHERE DateInserted <= '$MILESTONE';" >$WORKING_DIR/delete.sql
                echo `date +"%Y-%m-%d %H:%M:%S"`" purging data from $DBASE" >>$LOG
                echo "purging data from $DBASE" >&2
                # run the delete and capture the exit status from sqlite3 (not exit status from 'cat').
                if sqlite3 $DBASE < $WORKING_DIR/delete.sql; then
                    echo `date +"%Y-%m-%d %H:%M:%S"`" purged $RECORDS records from $DBASE. See $WORKING_DIR/remove_$MILESTONE.bak for backup records." >>$LOG
                    echo " purged $RECORDS records from $DBASE. See $WORKING_DIR/remove_$MILESTONE.bak for backup records." >&2
                    echo `date +"%Y-%m-%d %H:%M:%S"`" rebuilding indexes." >>$LOG
                    echo "rebuilding indexes." >&2
                    drop_indices
                    ensure_indices
                else
                    echo `date +"%Y-%m-%d %H:%M:%S"`"**error, failed to purged $RECORDS records from $DBASE. See $WORKING_DIR/delete.sql for information." >>$LOG
                    echo "**error, failed to purged $RECORDS records from $DBASE. See $WORKING_DIR/delete.sql for more information." >&2
                    exit $FALSE
                fi
            else
                echo `date +"%Y-%m-%d %H:%M:%S"`" no records selected to purge." >>$LOG
                echo "no records selected to purge." >&2
            fi
            exit $TRUE
        else
            echo `date +"%Y-%m-%d %H:%M:%S"`" aborting purge and exiting." >>$LOG
            echo "aborting purge and exiting." >&2
            exit $TRUE
        fi
        ;;
	x)	usage
		;;
    *)	usage
        echo "**error invalid option specified." >&2
		;;
  esac
done
exit $TRUE

# EOF

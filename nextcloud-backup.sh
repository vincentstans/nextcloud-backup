#!/bin/bash
# set userid for execution 0=root 33=www-data 1000=First User Created
uid=1000

## Set verbose 0=normal output 1=no output 2=no output only report
verbose=0

exec 3>&1 ## show stdout 1>&3
exec 4>&2 ## show strerr 2>&4

if ! ((verbose)); then
         echo "verbose set: $verbose"
   else
         exec 1>/dev/null
         exec 2>/dev/null
fi

## Argument 1 may be any number from 0-9 or -h or --help
ARG=$1
ARG1=$2
if [[ ! -z $ARG ]]; then
       if ! [[ "$1" == -h || "$1" == --help || "$1" =~ [0-9]$ ]]; then
                printf " \033[31m %s \n\033[0m" "not a valid argument" 1>&3
                exit 128
       fi
    else
        ## Set text style
        readonly ul=`tput smul`
        readonly nl=`tput rmul`
        readonly b=`tput bold`
        readonly n=`tput sgr0`
        readonly red='\033[31m'
fi


## This Script needs root access
## user www-data is id 33
SCRIPT=`basename ${BASH_SOURCE[0]}`
if ! [ $(id -u) = $uid ]; then
        echo -e "\n This ${ul}script${n} need to be run as ${red}root${n}.\n" >&2 1>&3
        exit 5
fi


## Nextcloud Settings Script
##
## for backing up Nextcloud
##
## for restoring Nextcloud
## $> echo SQL-root-password | base64 > db_auth.cfg && sed -i '1s/^/DB_NC=/' db_auth.cfg; sleep 2 && chmod 400
source db_auth.cfg
## Backup Location
BACKUP_DIR=''
## Nextcloud installation Directory
NCPATH='/var/www/nextcloud'
## Apache user
HTUSER='www-data'
HTGROUP='www-data'

### No edit beyond here

## Set Config location
config="${NCPATH}/config/config.php"

## Grab the current nextcloud version
VERSION=$(cat ${NCPATH}/version.php | head -n 2 | tail -n1 | awk '{ print $3 }' | cut -c 7-14 | sed 's/,/./g')

occ_call="sudo -u www-data php -f ${NCPATH}/occ"

## Maintenance Mode
getmm=$($occ_call config:system:get maintenance)
if [[ ${getmm} == *true* ]]; then
        MM='on'
    else
        MM='off'
fi

## Grab datadirectory
DATADIR="$($occ_call config:system:get datadirectory)"

## Grab Database name
DATABASE="$($occ_call config:system:get dbname)"

## Grab username
SQLUSER="$($occ_call config:system:get dbuser)"

## Grab passwords
DBP="$($occ_call config:system:get dbpassword)"

## Grab instanceID
iID=$(cat ${config} | grep instance | cut -d'>' -f2 | cut -c3-)
instanceID=${iID::-2}

## Required for DROP AND CREATE DATABASE for RESTORING
rdbp=$(eval echo ${DB_NC} | base64 -d)
mdbp=$(eval echo ${DB_PASS} | base64 -d)
rootuser='root'

## Creating Date variables
## start Week number %U=week start on sunday  %W=week start on monday
WEEK=$(date +%W)
## Start date/time backup
SBT=$(date +"%x-%H:%M")
## Current Weekday number %u sunday=7 monday=1, 1 == full backup / %w = sunday=0 monday=1
DOW=$(date +%u)

## Backup Nextcloud installation location
BACKUP_PATH="${BACKUP_DIR}/${WEEK}/${DOW}/nextcloud-${VERSION}-${SBT}"

## Backup Nextcloud User Data Location
BACKUP_DATA="${BACKUP_DIR}/${WEEK}/${DOW}/nextcloud-data-${VERSION}-${SBT}"

## Link to Latest Backup and SQL
LATEST_LINK="${BACKUP_DIR}/latest"

## Link to Latest Backup of User Data
LATEST_DATA="${BACKUP_DIR}/data"



function version {
if [[ -z $VERSION ]]; then
    printf "What version Nextcloud are you running\n" 1>&3 2>&4
    read -p "Version: " cversion 1>&3 2>&4
    VERSION=cversion
else
    if [[ $uid == 1000 ]]; then
        usage
    else
        startup
    fi
fi
}

## Start Writing Report Message / HTML
REPORT=$(printf "\n Backup Report \n")

function menu {
 echo 1>&3
 echo " Current Nextcloud Version: ${VERSION}" 1>&3
 echo 1>&3
 echo " Week nr: $WEEK, Day of the week: $DOW " 1>&3
 echo 1>&3
 echo " 1: Switch Maintenance Mode. Currently:'${MM}' " 1>&3
 echo " 2: Full BACKUP. " 1>&3
 echo " 3: Incremental BACKUP. " 1>&3
 echo " 4: RESTORE. " 1>&3
 echo " 5: Backup SQL. " 1>&3
 echo " 6: Unpack Old Backup. " 1>&3
if [[ ! -z $ARG ]]; then
    echo " 7: Remove backups. " 1>&3
    echo " 8: Compress a Backup Week '$SCRIPT' 8 [weeknr]"  1>&3
    echo " 11: Run script as cronjob " 1>&3
fi
 echo " 0: EXIT." 1>&3
 echo " 01: EXIT. Mail REPORT" 1>&3
 echo " 02: EXIT. Show REPORT" 1>&3
 echo " 03: EXIT. Show/Mail REPORT" 1>&3
 echo 1>&3
#echo "Maybe try \$ sudo bash -c ${SCRIPT} [NUMBER]" | pv -qL 25
}

REPORT+=$(printf "\n\n Week nr: $WEEK \n Day of the week: $DOW \n Current Nextcloud Version: ${VERSION} \n Date variable: ${SBT}")

function startup {
if [[ ! -z $ARG ]]; then

    if [[ $ARG == -h || $ARG == --help ]]; then
        usage
#        quit
    fi

    ans=$ARG
    finished=1
    REPORT+=$(printf "\n ${SCRIPT} Argument given: ${ARG}")
elif [[ $finished == "1" ]]; then
    quit
else
    menu
    read -n 2 -p " Selection: " ans 2>&4
    until [[ -z "$ans" || "$ans" =~ [0-8]$ ]]; do
        printf "${ans}: \033[31m %s \n\033[0m" "Invalid Selection." 1>&3
        echo "choose 1 thru 6 or 0 to exit." 1>&3
        read -n 2 -p " Selection: " ans 2>&4
    done
fi

if [[ $ans == "1" ]]; then
    REPORT+=$(printf "\n\n Selected Menu: $ans. Maintenance Mode")
    production
    ARG=
    startup
elif [[ $ans == "2" ]]; then
    REPORT+=$(printf "\n\n Selected Menu: $ans. Full Backup")
    full
    ARG=
    startup
elif [[ $ans == "3" ]]; then
    REPORT+=$(printf "\n\n Selected Menu: $ans. Incremental Backup")
    ibackup
    ARG=
    startup
elif [[ $ans == "4" ]]; then
    REPORT+=$(printf "\n\n Selected Menu: $ans. Restore Backup")
    restore
    ARG=
    startup
elif [[ $ans == "5" ]]; then
    REPORT+=$(printf "\n\n Selected Menu: $ans. SQL Backup")
    sqlbackup
    ARG=
    startup
elif [[ $ans == "6" ]]; then
    REPORT+=$(printf "\n\n Selected Menu: $ans. Entered Unpacking Selection")
    decompress
    ARG=
    startup
elif [[ $ans == "7" ]]; then
    REPORT+=$(printf "\n\n Entered Remove Backup")
    removeold
    ARG=
    startup
elif [[ $ans == "8" ]]; then
    compress_old $ARG1
    ARG=
    startup
elif [[ $ans == "11" && $ARG == "11" ]]; then
    REPORT+=$(printf "\n\n Running CRONJOB")
    if [[ $DOW == "1" ]]; then
        full
        quit
    else
        ibackup
        quit
    fi
elif [[ $ans == "01" ]]; then
    ans=11
    quit
elif [[ $ans == "02" ]]; then
    ans=02
    quit
elif [[ $ans == "03" ]]; then
    quit
elif [[ $ans == "0" ]]; then
    quit
elif [[ $ans -gt "8" ]]; then
    if [[ ! -z $ARG ]]; then
	    printf " \033[31m %s \n\033[0m" "not a valid argument" 1>&3
        exit 0
    fi
    printf "${ans}: \033[31m %s \n\033[0m" "Invalid Selection." 1>&3
    echo "choose 1 thru 9 or 0 to exit." 1>&3
    startup
fi
}


##-----------------------------##
##- Menu 1 # Maintenance Mode -##
##-----------------------------##
function production {
REPORT+=$(printf "\n\n Entered Maintenance Mode Menu")
printf "\n Maintenance Mode is set to '${MM}' \n"
if [[ ${MM} == off ]]; then
    prompt_confirm " Setting Maintenance Mode ON"
    if [[ $ans == [yY] ]]; then
        maintenance on
    else
        echo " Maintenance left ${MM}"
        REPORT+=$(printf "\n Maintenance not changed. status: ${MM}")
    fi
else
    prompt_confirm " Setting Maintenance Mode OFF"
    if [[ $ans == [yY] ]]; then
        maintenance off
    else
        echo " Maintenance left ${MM}"
        REPORT+=$(printf "\n Maintenance not changed. status: ${MM}")
    fi
fi
REPORT+=$(printf "\n Exited Maintenance Mode Menu")
printf "\n Maintenance mode. status: '${MM}' \n Finished"
press 3
}



##------------------------##
##- Menu 2 # Full Backup -##
##------------------------##
function full {
if [[ ! -d $BACKUP_DIR/$WEEK/$DOW/ ]]; then
   sudo -u ${HTUSER} mkdir -p $BACKUP_DIR/$WEEK/$DOW/
fi
REPORT+=$(printf "\n\n Started Full Backup on: $(date +%x-%H:%M:%S)")
rm "${LATEST_LINK}"
rm "${LATEST_LINK}.sql"
rm "${LATEST_DATA}"
compress_old $(( $(date +%W) - 1 ))
maintenance on
## backup Nextcloud installation /var/www/nextcloud
printf "\n Back-up ${NCPATH} to ${BACKUP_PATH} \n"
REPORT+=$(printf "\n\n Backup of ${NCPATH} started on: $(date +%x-%H:%M:%S)")
 rsync -ah --stats \
 ${NCPATH}/ \
 ${BACKUP_PATH}/ \
 &>/tmp/rsync.log
rout=$?
RSYNC=$(</tmp/rsync.log)
REPORT+=$(printf "\n rsync exit code $rout \n rsync output: \n${RSYNC}")
sudo -u ${HTUSER} ln -s "${BACKUP_PATH}" "${LATEST_LINK}"
rm /tmp/rsync.log
REPORT+=$(printf "\n Backup of ${NCPATH} completed on: $(date +%x-%H:%M:%S)")

## Backup USER DATA Directory
 printf "\n Back-up ${DATADIR} to ${BACKUP_DATA} \n"
REPORT+=$(printf "\n\n Backup of ${DATADIR} started on: $(date +%x-%H:%M:%S)")
 rsync -ah --stats \
 --exclude={'lost+found','updater-*'} \
 ${DATADIR}/ \
 ${BACKUP_DATA}/ \
 &>/tmp/rsync.log
rout=$?
REPORT+=$(printf "\n rsync exit code: $rout")
RSYNC=$(</tmp/rsync.log)
REPORT+=$(printf "\n rsync output: \n${RSYNC}")
sudo -u ${HTUSER} ln -s "${BACKUP_DATA}" "${LATEST_DATA}"
rm /tmp/rsync.log
REPORT+=$(printf "\n Backup of ${DATADIR} completed on: $(date +%x-%H:%M:%S)")

## Backup SQL DATABASE
 sqlbackup
 maintenance off
 printf "\n\n Full Back-up of Week $WEEK Completed on: $(date +%x-%H:%M:%S)"
 REPORT+=$(printf "\n\n Full Back-up of Week $WEEK Completed on: $(date +%x-%H:%M:%S)")
}

##-------------------------------##
##- Menu 3 # Incremental Backup -##
##-------------------------------##
function ibackup {
REPORT+=$(printf "\n\n Started Incremental Backup on: $(date +%x-%H:%M:%S)")
maintenance on
printf "\n Back-up ${NCPATH} \n"
if [[ ! -d $BACKUP_DIR/$WEEK/$DOW/ ]]; then
    sudo -u ${HTUSER} mkdir -p $BACKUP_DIR/$WEEK/$DOW/
fi
## Incremental backup Nextcloud installation /var/www/nextcloud
REPORT+=$(printf "\n\n Backup of ${NCPATH} started on: $(date +%x-%H:%M:%S)")
 rsync -avh --stats --delete ${NCPATH}/ \
 --link-dest "${LATEST_LINK}" \
 ${BACKUP_PATH}/ \
 &>/tmp/rsync.log
rout=$?
RSYNC=$(</tmp/rsync.log)
REPORT+=$(printf "\n rsync exit code: $rout\n rsync output: \n${RSYNC}\n\n Backup of ${NCPATH} completed on: $(date +%x-%H:%M:%S)")
rm /tmp/rsync.log

if [[ -d "${LATEST_LINK}" ]]; then
    echo
    rm "${LATEST_LINK}"
fi
sudo -u ${HTUSER} ln -s "${BACKUP_PATH}" "${LATEST_LINK}"
## Incremental backup USER DATA
printf "\n Back-up ${DATADIR} \n"
REPORT+=$(printf "\n\n Backup of ${DATADIR} started on: $(date +%x-%H:%M:%S)")
 rsync -avh --stats --delete \
  --exclude={'lost+found','updater-*'} \
  ${DATADIR}/ \
  --link-dest "${LATEST_DATA}" \
  ${BACKUP_DATA}/ \
  &>/tmp/rsync.log
rout=$?
RSYNC=$(</tmp/rsync.log)
REPORT+=$(printf "\n\nrsync exit code: $rout\n rsync output: \n${RSYNC}\n\n Backup of ${DATADIR} completed on: $(date +%x-%H:%M:%S)")
rm /tmp/rsync.log
 if [[ -d "${LATEST_DATA}" ]]; then
     echo
     rm "${LATEST_DATA}"
 fi
 sudo -u ${HTUSER} ln -s "${BACKUP_DATA}" "${LATEST_DATA}"

## Backup SQL DATABASE
sqlbackup
maintenance off
delsql $(( ${DOW} - 2 ))
printf "\n\n Incremental Back-up of Day $DOW $(date +%A) Completed on: $(date +%x-%H:%M:%S)"
REPORT+=$(printf "\n\n Incremental Back-up of Day $DOW $(date +%A) Completed on: $(date +%x-%H:%M:%S)")
}

##---------------------------##
##- Menu 4 # Restore Backup -##
##---------------------------##
function restore {
REPORT+=$(printf "<br /><br /> Restore mode Started")
seek=(${BACKUP_DIR}/*/*/*.sql)
look ${seek}QRestoreQBackup
selected_dir="${seek[$((selection-1))]::-4}"
selected_date=$(echo ${selected_dir} | cut -d'/' -f6- | sed 's/nextcloud-//')
map=$(echo ${selected_dir} | cut -d'/' -f1-5)
selected_bckup="${map}/nextcloud-data-${selected_date}"
REPORT+=$(printf "<br /> You selecHted Backup: '${selected_dir:39}'")
echo 1>&3
echo " This will move ${NCPATH} to ${NCPATH}_old "
prompt_confirm " Restore backup of ${selected_dir:29} to ${NCPATH} "
if [[ $ans == [yY] ]]; then
    maintenance on
    echo " Moving ${NCPATH} to ${NCPATH}_old "
    echo
#   mv ${NCPATH} /var/www/nextcloud_old
    echo " Restoring ${selected_dir:29} to ${NCPATH} "
    echo
#    rsync -Aaxh ${selected_dir} ${NCPATH}
    REPORT+=$(printf "<br /><br /> RESTORED ${selected_dir:29} to ${NCPATH}")
else
    REPORT+=$(printf "<br /><br /> NOT RESTORED ${selected_dir:29} to ${NCPATH}")
    echo " Not Restoring"
fi

prompt_confirm " Restore SQL DATABASE ${selected_dir:29}.sql"
if [[ $ans == [yY] ]]; then
    if [[ $MM == off ]]; then
        echo
        maintenance on
    fi
    echo " DROP DATABASE ${DATABASE}"
    echo
#   mysql -u ${rootuser} -p${rdbp} -e "DROP DATABASE ${DATABASE}"
    REPORT+=$(printf "<br /><br /> DROPPED DATABASE ${DATABASE}")
    echo " Creating DATABASE ${DATABASE}"
    echo
#   mysql -u ${rootuser} -p${rdbp} -e "CREATE DATABASE ${DATABASE} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
    mout=$?
    REPORT+=$(printf "<br /> CREATED DATABASE ${DATABASE} \n mysql exit code: $mout")
    echo " Restoring backup SQL file from ${selected_dir}.sql "
    echo 1>&3
#   mysql -u ${rootuser} -p${rdbp} ${DATABASE} < ${selected_dir}.sql
    mout=$?
    REPORT+=$(printf "<br /> RESTORED DATABASE ${DATABASE} from ${selected_dir:29}.sql <br /> mysql exit code: $mout")
else
    echo " Not Restoring SQL DATABASE"
    REPORT+=$(printf "<br /> NOT RESTORED ${selected_dir:29}.sql")
fi

prompt_confirm " Restore USER DATA ${selected_bckup:29} to ${DATADIR} "
if [[ $ans == [yY] ]]; then
    if [[ $MM == off ]]; then
        echo
        maintenance on
    fi
    echo " Restoring ${selected_bckup:29} to ${DATADIR} "
#   rsync -Aaxh ${selected_bckup} ${DATADIR}
    REPORT+=$(printf "<br /><br /> RESTORED ${selected_bckup:29} to ${DATADIR}")
else
    echo " Not Restoring USER DATA"
    REPORT+=$(printf "<br /><br /> NOT RESTORED ${selected_bckup:29} to ${DATADIR}")
fi

if [[ $MM == on ]]; then
    echo
    maintenance off
fi
## TODO: Set nextcloud occ rapair commands
}


##--------------------------------##
##- Menu 5 # Backup SQL DATABASE -##
##--------------------------------##
function sqlbackup {
REPORT+=$(printf "\n\n Backup of DATABASE ${DATABASE} started on: $(date +%x-%H:%M:%S)")

if [[ $MM == off ]]; then
    maintenance on
fi
REPORT+=$(printf "\n Back-up SQL Database to ${BACKUP_PATH}.sql")
printf "\n Back-up SQL Database to ${BACKUP_PATH}.sql \n"
mysqldump --single-transaction --default-character-set=utf8mb4 -u ${SQLUSER} -p${DBP} ${DATABASE} > ${BACKUP_PATH}.sql
mout=$?
REPORT+=$(printf "\n mysqldump exit code: $mout")
printf "\n mysqldump exit code: $mout"
chown ${HTUSER}:${HTGROUP} ${BACKUP_PATH}.sql

if [[ -f "${LATEST_LINK}.sql" ]]; then
    echo
    rm "${LATEST_LINK}.sql"
fi
sudo -u ${HTUSER} ln -s "${BACKUP_PATH}.sql" "${LATEST_LINK}.sql"

if [[ $finished == 1 && $ARG == 5 || $ans == 5 ]]; then
    maintenance off
fi
sudo -u www-data sed -i "/Database: nextcloud/i-- Nextcloud Version: ${VERSION}" ${BACKUP_PATH}.sql
REPORT+=$(printf "\n Backup of DATABASE ${DATABASE} completed on: $(date +%x-%H:%M:%S)")
head -n6 ${BACKUP_PATH}.sql > /tmp/fogd
REPORT+=$(printf "\n\n mysqldump head: \n $(cat /tmp/fogd) ")
rm /tmp/fogd
}


##--------------------------##
##- Menu 6 # Unpack Backup -##
##--------------------------##
function decompress {
seek=($BACKUP_DIR/*.tar)
if [[ -f $seek ]]; then
    look ${seek}QUnpackQBackup
    selected_zip="${seek[$((selection-1))]}"
    echo "You selected '$selected_zip'" 1>&3

    prompt_confirm "Unpack $selected_zip"
    if [[ $ans == [yY] ]]; then
#        bzip2 -d "${selected_zip}"
#        bout=$?
        tar -xpf "${selected_zip::-4}" -C /
        tout=$?
        rm ${selected_zip::-4}
    else
        echo " Nothing Unpacked "
        press 5
    fi

    prompt_confirm " Unpack Another ?"
    if [[ $ans == [yY] ]]; then
        decompress
    fi

else
    echo "Found nothing " 1>&3
    press 5
fi
}


##----------------------------##
##- Menu 7 # Delete a Backup -##
##----------------------------##
function removeold {
seek=(${BACKUP_DIR}/*/[0-9]/)
if [[ -d $seek ]]; then
    look ${seek}QRemoveQBackup
    selected_backup="${seek[$((selection-1))]}"
    del_week=$(echo "$selected_backup" | cut -d'/' -f4-)
    echo "You selected '$selected_backup'" 1>&3
    prompt_confirm " Remove backup of Week/Day '$del_week'"

    if [[ $ans == [yY] ]]; then
        rm -Rf "${selected_backup}"
        REPORT+=$(printf "\n\n Removed Week/Day: $del_week - ${selected_backup}")
    else
        echo " Nothing removed "
        press 3
    fi

    prompt_confirm " Remove Another ?"

    if [[ $ans == [yY] ]]; then
        removeold
    else
        return 0
    fi

else
    echo "Found nothing " 1>&3
    press 3
fi
}


##---------------------------------------
## Menu 8 [WeekNR] # Compress Backup Week
##---------------------------------------
function compress_old () {
REPORT+=$(printf "\n\n Entered Compression.")
old_week=$1

if [[ -z $old_week ]]; then
#    read -p " Compress Which Week?: " old_week
    until [[ $old_week =~ [0-9] || $old_week == [mM] ]]; do
        echo " Enter a Week Number. or M for Menu " 1>&3
        read -p " Compress Which Week?: " old_week
    done

	if [[ $old_week == [mM] ]]; then
        return 1
        menu
	fi
fi

echo "Selected week: $old_week"

if [[ -d ${BACKUP_DIR}/$old_week ]]; then
    REPORT+=$(printf "\n\n Compressing ${BACKUP_DIR}/$old_week")
    echo "Compressing ${BACKUP_DIR}/$old_week"
    sudo -u ${HTUSER} tar -cpf ${BACKUP_DIR}/$old_week.tar ${BACKUP_DIR}/$old_week
    tout=$?
    rm -Rf ${BACKUP_DIR}/$old_week
#     bzip2 -9 ${BACKUP_DIR}/$old_week.tar
#    bout=$?
#    REPORT+=$(printf "\n Tar exit code: $tout.\n bzip2 exit code: $bout.\n Completed Compression.")
else
    REPORT+=$(printf "\n No backup of week $old_week Found \n Exited Compression ")
    echo " No Backup of week $old_week Found. "
fi

REPORT+=$(printf "\n\n Exited Compression on: $(date +%x-%H:%M:%S)")
}



maintenance () {
REPORT+=$(printf "\n\n Entered Maintenance Mode Menu")
if [[ $1 == off && ! ${MM} == off ]]; then
    REPORT+=$(printf "\n Turning maintenance:mode --off")
    printf "\n Turning maintenance:mode --off \n"
    sudo -u ${HTUSER} php ${NCPATH}/occ maintenance:mode --off
    MM='off'
elif [[ $1 == on && ! ${MM} == on ]]; then
    REPORT+=$(printf "\n Turning maintenance:mode --on")
    printf "\n Turning maintenance:mode --on \n"
    sudo -u ${HTUSER} php ${NCPATH}/occ maintenance:mode --on
    MM='on'
else
    printf "\n Maintenance not changed"
    REPORT+=$(printf "\n Maintenance not changed. status: ${MM}")
fi
REPORT+=$(printf "\n Exited Maintenance Mode Menu")
}



delsql() {
REPORT+=$(printf "\n\n Entered SQL Clean up ")
 if [[ ! ${DOW} =~ ^(1|2)$ ]]; then
      echo " Removing Previous SQL"
    old_day=$1
    old_sql=(${BACKUP_DIR}/${WEEK}/$old_day/*.sql)

      if [[ -f $old_sql ]]; then
         REPORT+=$(printf "\n Removing: $old_sql ")
          echo " Removing: $old_sql "
          rm $old_sql
       else
         REPORT+=$(printf "\n No old SQL backup Found ")
          echo " No SQL File Found "
      fi

    REPORT+=$(printf "\n Finished SQL Clean up")
     echo " Finished SQL Clean up "
  else
    REPORT+=$(printf "\n No SQL Backup to Clean up.")
 fi
}



look() {
seek=$(echo $1 | cut -d'Q' -f1)
title=$(echo $1 | cut -d'Q' -f2)
subj=$(echo $1 | cut -d'Q' -f3)
 read -p "$(
    c=0
    for files in "${seek[@]}" ; do
        echo "$((++c)): $files"
    done
    echo  'Your about to '${title}' !!! '
    echo -ne 'Please select a '${subj}' > '
 )" selection 2>&4
}



prompt_confirm() {
 while true; do
    read -r -n 1 -p "${1:-Continue?} [y/n]: " ans 2>&4
    case $ans in
        [yY]) echo 1>&3; return 0 ;;
        [nN]) echo 1>&3; return 1 ;;
        *) printf " \033[31m %s \n\033[0m" "invalid input" 1>&3
    esac
 done
}



press() {
 read -t $1 -n 1 key
}



sendmessage() {
 clear
 echo "${1}"

 if [[ $verbose == 2 || $ans == 02 || $ans == 03 ]]; then
    clear 1>&3
    echo "${1}" 1>&3
 fi
}



## Menu 0 # Clean script exit
function quit {
 REPORT+=$(printf "\n\n END of REPORT")
 sendmessage "${REPORT}"
 echo 1>&3
 echo "Peace out." 1>&3
 exec 3>&-
 exec 4>&-
 exit 0
}



function usage {
if [[ -z ${BACKUP_DIR} ]]; then
    printf "\n\n No Backup Directory set \n Please Enter a mount point." 1>&3
    read -p " > " link
    sed -i "/^BACKUP_DIR=/cBACKUP_DIR='$link'" ${SCRIPT}
fi
printf "\n\n This script makes a copy of: \n Nextcloud installation directory \n Nextcloud UserData \n MySQL Database" 1>&3
printf "\n\n Please check that the following settings are correct: \n Running NC Version: ${VERSION} \n ${ul}Nextcloud Installation Directory${n}: ${red}${b}${NCPATH}${n}" 1>&3
printf "\n ${ul}Nextcloud Backup location${n}: ${red}${b}${BACKUP_DIR}${n}" 1>&3
printf "\n\n You can run this script as a cronjob by adding ${b}${SCRIPT} 11${n} to your root's crontab" 1>&3
printf "\n It will make a full backup every monday and a Incremental backup every other day of the week" 1>&3
printf "\n MySQL backup will be saved for 2 days" 1>&3
printf "\n At the end of the week the backup will be compressed to ${BACKUP_DIR}/[week_number].tar" 1>&3
printf "\n The Folder structure will be: \n ${BACKUP_DIR}/week_number/day_number/ " 1>&3
if [[ $uid == 1000 ]]; then
    printf "\n\n This script needs to be run as ${red}root${n}\n" 1>&3
    prompt_confirm " Set Root " || exit 1
    sed -i "/^uid=1000/cuid=0" ${SCRIPT}
    echo 1>&3
    exit 5
fi
echo 1>&3
exit 4
}

# First action Check if we have a nextcloud version
version
## Faulty script exit
echo " foo "

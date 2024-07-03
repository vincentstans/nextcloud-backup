#!/bin/bash
#
# Vincent Stans
#
pid=$!
source colors.var
E() { local MSSG="${@}";echo -en "${GREEN}$logd${NC} Error: ${MSSG}\n"; }
if ! [[ -z $1 ]]; then if [[ $1 == "-H" ]]; then lines=`wc -l $0|awk '{print $1}'`;sed "${lines}"d $0|md5sum|base64; exit 0; fi; E "Not supported";exit 1; fi 
VALID=`lines=$(wc -l $0|awk '{print $1}');sed "${lines}"d $0|md5sum|base64`
CHECK=`tail -n1 $0|cut -d# -f2`
if ! [[ $CHECK == $VALID ]]; then E "${GRAY} Someone ${UL}${RED}changed${NC}${GRAY} the script!${NC}."; exit 1; fi
if ! [ $(id -u) = "0" ]; then
		E "${GRAY}This ${UL}${GREEN}script${NC}${GRAY} need to be run as ${RED}root${NC}."
        exit 5
fi
# Where to backup to.
desta="/srv/backups"
destb="/mnt/backups/Remote"
# log file
log="/var/log/backup-nc-sql.log"
echo ' ' > $log
logd=$(date "+%Y%m%d%H%M%S")
day=$(date +%d-%m-%y)
_HTUSER='www-data' # change webserver-user accordingly:
_NCPATH='/var/www/nextcloud'  # ADJUST NC Installation location 
_OCC="sudo -u ${_HTUSER} php ${_NCPATH}/occ"
_DBNAME="$($_OCC config:system:get dbname)"
_DBPREFIX="$($_OCC config:system:get dbtableprefix)"
_DBUSER="$($_OCC config:system:get dbuser)"
_DBPASSWORD="$($_OCC config:system:get dbpassword)"
_VERSION="$($_OCC config:system:get version)"
## Link to Latest SQL Backup
LATEST_LINK="${desta}/latest.sql.aes"
archive_file="nextcloud-${_VERSION}-${day}.sql"
L() { local LOG="${@}"; echo -ne "${GREEN}$logd${NC} ${LOG}\n";echo "$logd ${LOG}" >> $log; }
L "Starting SQL backup:"
MAINTENANCE() {
_OPT="$1"
if ! [[ -z ${_OPT} ]]; then
$_OCC maintenance:mode --${_OPT}
fi
_MAINTENANCE=$($_OCC maintenance:mode)
}
MAINTENANCE
L "check maintenance mode: $_MAINTENANCE"
if ! [[ $_MAINTENANCE == *enabled* ]];then
 MAINTENANCE on
 L "Maintenance set $_MAINTENANCE"
 else
 L "Maintenance already set $_MAINTENANCE"
fi
L "Back-up SQL Database to $desta/$archive_file ... "
mysqldump --single-transaction --default-character-set=utf8mb4 -u ${_DBUSER} -p${_DBPASSWORD} ${_DBNAME} > $desta/$archive_file
mout=$?
L "mysqldump exit code $mout"
L "Turning off maintenance mode "
MAINTENANCE off
if [[ -f "${LATEST_LINK}" ]]; then
	L "Removing Old Latest Link"
    rm "${LATEST_LINK}"
    sleep 1
fi
sudo -u ${_HTUSER} sed -i "/Database: nextcloud/i-- Nextcloud Version: ${_VERSION}" $desta/$archive_file
L "Encrypting file $desta/$archive_file"
openssl aes-256-cbc -e -pbkdf2 -in $desta/$archive_file -k `echo ${archive_file:0:-4}|rev|xxd -p|base64` -out $desta/$archive_file.aes
L "Shred original dump"
shred -n 7 -z -u $desta/$archive_file
archive_file=$archive_file.aes
ln -s "${desta}/${archive_file}" "${LATEST_LINK}"
chown ${_HTUSER}:${_HTUSER} $desta/$archive_file
L "Moving offsite..."
rsync -Pz --bwliimit=2560 "$desta/$archive_file" \
 --link-dest="${LATEST_DATA}" \
 "$destb/$archive_file"
L "Removing out of date backups..."
number_current=$(find $destb -name "*.sql.aes" -type f -mtime -16 | wc -l)
if [[ $number_current -ge 1 ]]; then
  find $destb -name "*.sql.aes" -type f -mtime +16 -delete
  L "Removed $number_current stale backup(s)..."
fi
L "Checking MD5 HASH..."
diff <( cd $desta;md5sum $archive_file ) <( cd $destb;md5sum $archive_file )
sum=$?
if ! [[ $sum == 0 ]]; then E "${UL}MD5SUM${NC} does not ${RED}match${NC}"; exit $sum; else L "MD5SUM check complete exited: $sum"; fi
L "SQL Backup complete!"
exit 0

#Y2IyNjA4YzUyZjU2ODM1YWQ5NWJhZWQyYjczYjNjOGQgIC0K

#!/bin/bash
FAIL=0
HOSTNAME=$(hostname)
TODAY=`/bin/date +%Y-%m-%d`
LOGFILE=/var/log/rclone/rclone-$TODAY.log
/usr/bin/mkdir -p /var/log/rclone/

REMOTE_BASE="mastodon-bkp:/mastodon-bkp"
touch $LOGFILE
chmod 640 $LOGFILE

# backup postgres database.
# Get postgres credentials from env file, caution with permissions on this file (chmod root, chown 600).
. /opt/mastodon-docker/database.env
echo ">>> Database Backup: " $POSTGRES_DB >>$LOGFILE
PGPASSWORD=$POSTGRES_PASSWORD docker exec -it mastodon-docker-postgresql-1 bash -c "pg_dump -U $POSTGRES_USER $POSTGRES_DB" |/bin/gzip - |/usr/bin/rclone -l -v --log-file=$LOGFILE rcat $REMOTE_BASE/dbbackups/$POSTGRES_DB-$TODAY.sql.gz
FAIL=$(( FAIL + $? ))

# save ACL permissions (small and useful)
echo ">>> Getting file's ACL..." >>$LOGFILE
/usr/bin/getfacl -R /etc /opt 2>/dev/null |/bin/gzip - |/usr/bin/rclone -l -v --log-file=$LOGFILE rcat $REMOTE_BASE/filebackups/$HOSTNAME-$TODAY.acl.gz
FAIL=$(( FAIL + $? ))

# backup our dpkg selections
echo ">>> Getting dpkg selections..." >>$LOGFILE
/usr/bin/dpkg --get-selections |/bin/gzip - |/usr/bin/rclone -l -v --log-file=$LOGFILE rcat $REMOTE_BASE/filebackups/$HOSTNAME-dpkg-selections.gz
FAIL=$(( FAIL + $? ))

# backup host server settings
SOURCE="/etc/"
echo ">>> $SOURCE" >>$LOGFILE
/usr/bin/rclone -l -v --log-file=$LOGFILE sync $SOURCE $REMOTE_BASE/filebackups$SOURCE \
 --backup-dir $REMOTE_BASE/differential/$TODAY/$SOURCE
FAIL=$(( FAIL + $? ))

# backup mastodon docker files
SOURCE="/opt/mastodon-docker/"
echo ">>> $SOURCE" >>$LOGFILE
/usr/bin/rclone -l -v --log-file=$LOGFILE sync $SOURCE $REMOTE_BASE/filebackups$SOURCE \
 --backup-dir $REMOTE_BASE/differential/$TODAY/$SOURCE
FAIL=$(( FAIL + $? ))

# backup for mastodon data
SOURCE="/opt/mastodon-data/web/"
echo ">>> $SOURCE" >>$LOGFILE
/usr/bin/rclone -l -v --log-file=$LOGFILE sync $SOURCE $REMOTE_BASE/filebackups$SOURCE \
 --backup-dir $REMOTE_BASE/differential/$TODAY/$SOURCE
FAIL=$(( FAIL + $? ))

# backup our mastodon scripts
SOURCE="/opt/mastodon-scripts/"
echo ">>> $SOURCE" >>$LOGFILE
/usr/bin/rclone -l -v --log-file=$LOGFILE sync $SOURCE $REMOTE_BASE/filebackups$SOURCE \
 --backup-dir $REMOTE_BASE/differential/$TODAY/$SOURCE
FAIL=$(( FAIL + $? ))

# backup this (and other) scripts
SOURCE="/opt/scripts/"
echo ">>> $SOURCE" >>$LOGFILE
/usr/bin/rclone -l -v --log-file=$LOGFILE sync $SOURCE $REMOTE_BASE/filebackups$SOURCE \
 --backup-dir $REMOTE_BASE/differential/$TODAY/$SOURCE
FAIL=$(( FAIL + $? ))

#
SOURCE="another-remote:/source-dir/"
echo ">>> $SOURCE" >>$LOGFILE
/usr/bin/rclone -l -v --log-file=$LOGFILE sync $SOURCE $REMOTE_BASE/filebackups/destination-directory/ \
 --backup-dir $REMOTE_BASE/differential/$TODAY/backup-source-name/ \
 --exclude "cache/**"
FAIL=$(( FAIL + $? ))

if [ $FAIL -ne 0 ]; then # alert on e-mail that backup failed
  cat $LOGFILE | /usr/bin/mailx -s "[$HOSTNAME b2 backup] failed: " notification@email.goes.here,another@email.goes.here
else # reset pull notfication timer: backup is OK
  /usr/bin/curl -s "https://heartbeat.uptimerobot.com/push-link-key-goeshere" >/dev/null
fi
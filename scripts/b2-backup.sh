#!/bin/bash

# This script uses rclone as backup tool
# makes backup of ACL, dpkg package list, mysql and files, keeping reverse differential

# Roadmap:
# - Finish postgresql method
# - Include and exclude files/directories
# - Databases lists
# - Method to get databases from SGBDs
# - Unify connection and direct DB dump methods
# - Mongo backup (simple mongodump)
# - Separate config file

FAIL=0
HOSTNAME=`hostname -s`
TODAY=`/bin/date +%Y-%m-%d`
LOGFILE=/var/log/rclone/rclone-$TODAY.log

# Multiple e-mails can be set with comma, without spaces.
EMAIL="roberto@provider.com"
SUCCESS_WEBHOOK="https://push.statuscake.com/?PK=SOME-VALID-KEY&TestID=NUMERIC-TEST-ID&time=0"
# Rclone endpoint
STORAGE="brnewsmt-bkp:brnewsmt"

# to get separate parameters use as: "${FILES_FROM[@]}"
FILES_FROM=( "/etc" \
            "/var/www" \
            "/home/user" \
           )

/usr/bin/mkdir -p `dirname $LOGFILE`
touch $LOGFILE
chmod 640 $LOGFILE

# backup postgres database. TODO: finish code
# Get postgres credentials from env file, caution with permissions on this file (chmod root, chown 600).
backup_postgres() {
    . /opt/mastodon-docker/database.env
    echo ">>> Database Backup: " $POSTGRES_DB >>$LOGFILE
    PGPASSWORD=$POSTGRES_PASSWORD docker exec -it mastodon-docker-postgresql-1 bash -c "pg_dump -U $POSTGRES_USER $POSTGRES_DB" | /bin/gzip - | /usr/bin/rclone -l -v --log-file=$LOGFILE rcat $REMOTE_BASE/dbbackups/$POSTGRES_DB-$TODAY.sql.gz
    FAIL=$(( FAIL + $? ))
}

# arguments: host, user, password, database
backup_mysql() {
    echo ">>> Database Backup: " $4 >>$LOGFILE
    MYSQL_PWD=$3 /usr/bin/mysqldump -h $1 -u $2 $4 | /bin/gzip - | /usr/bin/rclone -l -v --log-file=$LOGFILE rcat $STORAGE/var/backups/mysql/$4-$TODAY.sql.gz
    FAIL=$(( FAIL + $? ))
}

# arguments: database
backup_mysql_local_root() {
    echo ">>> Database Backup: " $1 >>$LOGFILE
    /usr/bin/mysqldump $1 | /bin/gzip - | /usr/bin/rclone -l -v --log-file=$LOGFILE rcat $STORAGE/var/backups/mysql/$1-$TODAY.sql.gz
    FAIL=$(( FAIL + $? ))
}

backup_acl() {
    echo ">>> Getting file's ACL..." >>$LOGFILE
    /usr/bin/getfacl -R "${FILES_FROM[@]}" 2>/dev/null |/bin/gzip - | /usr/bin/rclone -l -v --log-file=$LOGFILE rcat $STORAGE/var/backups/$HOSTNAME-$TODAY.acl.gz
    FAIL=$(( FAIL + $? ))
}

backup_dpkg() {
    echo ">>> Getting dpkg selections..." >>$LOGFILE
    /usr/bin/dpkg --get-selections |/bin/gzip - | /usr/bin/rclone -l -v --log-file=$LOGFILE rcat $STORAGE/var/backups/$HOSTNAME-dpkg-selections.gz
    FAIL=$(( FAIL + $? ))
}

backup_files_with_reverse_diff() {
    echo ">>> Backing up files..." >>$LOGFILE
    for DIRECTORY in "${FILES_FROM[@]}"; do
        echo " -> $SOURCE" >>$LOGFILE
        /usr/bin/rclone -l -v --log-file=$LOGFILE sync "$DIRECTORY"	"$STORAGE$DIRECTORY" \
            --backup-dir "$STORAGE/differential/$TODAY$DIRECTORY" ;
        FAIL=$(( FAIL + $? ));
    done
}

#backup_mysql localhost user-name [some-passwd] wp_database
backup_mysql_local_root wp_database

backup_acl

backup_dpkg

backup_files_with_reverse_diff

if [ $FAIL -eq 0 ]; then
  /usr/bin/curl -s "$SUCCESS_WEBHOOK" >/dev/null
else
  cat $LOGFILE | /usr/bin/mailx -s "[$HOSTNAME b2 backup] failed" $EMAIL
fi

#!/bin/sh

set -e

stop=0
# Check required environment variables.
[ "$WP_ENV"           == "" ] && echo "[!!!] Please set WP_ENV in your .env file." && stop=1 || \
if [ "$WP_ENV" != development ] && [ "$WP_ENV" != production ]; then
  echo "[!!!] Invalid value for WP_ENV. Please set WP_ENV to either 'development' or 'production' in your .env file."
  stop=1
fi
[ "$WP_HOME"          == "" ] && echo "[!!!] Please set WP_HOME in your .env file." && stop=1
[ "$WP_SITEURL"       == "" ] && echo "[!!!] Please set WP_SITEURL in your .env file." && stop=1
[ "$DB_USER"          == "" ] && echo "[!!!] Please set DB_USERNAME in your .env file." && stop=1
[ "$DB_PASSWORD"      == "" ] && echo "[!!!] Please set DB_PASSWORD in your .env file." && stop=1
[ "$DB_NAME"          == "" ] && echo "[!!!] Please set DB_DATABASE in your .env file." && stop=1
[ "$DB_CHARSET"       == "" ] && echo "[!!!] Please set DB_CHARSET in your .env file." && stop=1
[ "$DB_TABLE_PREFIX"  == "" ] && echo "[!!!] Please set DB_TABLE_PREFIX in your .env file." && stop=1
[ "$AUTH_KEY"         == "" ] && echo "[!!!] Please set AUTH_KEY in your .env file." && stop=1
[ "$SECURE_AUTH_KEY"  == "" ] && echo "[!!!] Please set SECURE_AUTH_KEY in your .env file." && stop=1
[ "$LOGGED_IN_KEY"    == "" ] && echo "[!!!] Please set LOGGED_IN_KEY in your .env file." && stop=1
[ "$NONCE_KEY"        == "" ] && echo "[!!!] Please set NONCE_KEY in your .env file." && stop=1
[ "$AUTH_SALT"        == "" ] && echo "[!!!] Please set AUTH_SALT in your .env file." && stop=1
[ "$SECURE_AUTH_SALT" == "" ] && echo "[!!!] Please set SECURE_AUTH_SALT in your .env file"
[ "$LOGGED_IN_SALT"   == "" ] && echo "[!!!] Please set LOGGED_IN_SALT in your .env file." && stop=1
[ "$NONCE_SALT"       == "" ] && echo "[!!!] Please set NONCE_SALT in your .env file." && stop=1

# Check directories.
for d in wp-content wp-content/plugins wp-content/themes wp-content/uploads; do
  if ! test -d "/var/www/html/$d"; then
    echo "[!!!] Directory /var/www/html/wp-content/$d/ not found. Please mount it in your docker-compose.yml"
    stop=1
  fi
done

# Stop if anything is wrong.
[ "$stop" == '1' ] && exit 1 || unset stop

# Set the UID and GID for the daemon
sed -Ei -e '/^www-data:/{s,:82:82:,:'${DAEMON_UID:-1000}:${DAEMON_GID:-1000}':,}' /etc/passwd*
sed -Ei -e '/^www-data:/{s,:82:,:'${DAEMON_GID:-1000}':,g}' /etc/group*

# Do not allow a wp-config.php inside /var/www/html/
if [ -f /var/www/html/wp-config.php ]; then
  echo "[!!!] /var/www/html/wp-config.php removed. Your configuration should be set in the .env file"
  rm /var/www/html/wp-config.php
fi

# Create empty access.log and error.log files if they don't exist
test -e /var/log/php-fpm/access.log || touch /var/log/php-fpm/access.log
test -e /var/log/php-fpm/error.log  || touch /var/log/php-fpm/error.log

# Change owner and group of all writable files to www-data:www-data
chown -R www-data:www-data /var/www/html/ /var/log/php-fpm/ /var/cache/php-opcache/

# Create /var/www/wp-config.php from the environment variables
echo '<?php' >/var/www/wp-config.php
echo "define( 'DB_HOST', 'mariadb' );" >>/var/www/wp-config.php
echo "define( 'DISALLOW_FILE_EDIT', true );" >>/var/www/wp-config.php
vars="
  WP_ENV            WP_HOME           WP_SITEURL        DB_USER
  DB_PASSWORD       DB_NAME           DB_CHARSET        DB_COLLATE
  AUTH_KEY          SECURE_AUTH_KEY   LOGGED_IN_KEY     NONCE_KEY
  AUTH_SALT         SECURE_AUTH_SALT  LOGGED_IN_SALT    NONCE_SALT
"
for var in $vars; do
  echo "define( '$var', '$(eval echo \$$var)' );" >>/var/www/wp-config.php
  if [ "$var" != "WP_ENV" ]; then
    unset $var
  fi
done
echo '$table_prefix = '"'$DB_TABLE_PREFIX';" >>/var/www/wp-config.php
unset DB_TABLE_PREFIX
(
  echo "if ( ! defined( 'ABSPATH' ) ) { define( 'ABSPATH', __DIR__ . '/' ); }"
  echo "require_once ABSPATH . 'wp-settings.php';"
) >>/var/www/wp-config.php

# Silence is golden.
for d in wp-content wp-content/plugins wp-content/themes wp-content/uploads; do
  d="/var/www/html/$d"
  echo -e '<?php\n// Silence is golden.' >"/var/www/html/$d/index.php"
done

# Set snuffleupagus secret key.
SNUFFLEUPAGUS_SECRET_KEY=$(base64 /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 64)
sed -i -E \
  -e 's,# (sp.global.secret_key)\(.*\);,\1("'"$SNUFFLEUPAGUS_SECRET_KEY"'"),g' \
  -e 's,"PHPSESSID","WP_PHPSESSID",g' \
  /usr/local/etc/php/conf.d/snuffleupagus.rules
unset SNUFFLEUPAGUS_SECRET_KEY

# Run php-fpm if no command is passed.
if [ "${1#-}" != "$1" ]; then set -- php-fpm "$@"; fi

# If the command is php-fpm, then do a few integritiy checks.
if [ "$1" = 'php-fpm' ]; then
  wp core verify-checksums || {
    echo "[!!!] Checksums of Wordpress core files are not valid. Please run 'wp core verify-checksums' manually."
    exit 1 # Any change in the WordPress core files is a fatal error.
  }
  while ! nc -z mariadb 3306; do
    sleep 0.2
  done
  wp plugin verify-checksums --all || {
    echo "[!!!] Checksums of Wordpress plugins are not valid. Please run 'wp plugin verify-checksums --all' manually."
    # Changes in the WordPress plugins are just warnings, cecause plugins
    # that are not obtained from the WordPress.org repository cannot be
    # verified.
  }
fi
exec "$@"

#!/bin/sh

sed -Ei -e '/^www-data:/{s,:82:82:,:'${DAEMON_UID:-1000}:${DAEMON_GID:-1000}':,}' /etc/passwd*
sed -Ei -e '/^www-data:/{s,:82:,:'${DAEMON_GID:-1000}':,g}' /etc/group*

if [ -f /var/www/html/wp-config.php ]; then
  echo "[!!!] '/var/www/html/wp-config.php' removed, please set your configuration in .env"
  rm /var/www/html/wp-config.php
fi

# Create empty access.log and error.log files if they don't exist
test -e /var/log/php-fpm/access.log || touch /var/log/php-fpm/access.log
test -e /var/log/php-fpm/error.log  || touch /var/log/php-fpm/error.log

# Change owner and group of all writable files to www-data:www-data
chown -R www-data:www-data /var/www/html/ /var/log/php-fpm/ /var/cache/php-opcache/

echo '<?php' > /var/www/wp-config.php
echo "define( 'DB_HOST', 'mariadb' );" >> /var/www/wp-config.php
echo "define( 'DISALLOW_FILE_EDIT', true );" >> /var/www/wp-config.php
vars="
  WP_ENV
  WP_HOME
  WP_SITEURL
  DB_USER
  DB_PASSWORD
  DB_NAME
  DB_CHARSET
  DB_COLLATE
  AUTH_KEY
  SECURE_AUTH_KEY
  LOGGED_IN_KEY
  NONCE_KEY
  AUTH_SALT
  SECURE_AUTH_SALT
  LOGGED_IN_SALT
  NONCE_SALT
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
  if [ ! -f "$d/index.php" ]; then
    echo -e '<?php\n// Silence is golden.' > "$d/index.php"
  else
    if [ "$(sha1sum "$d/index.php" | cut -d' ' -f1)" != "805d36c17119a980e4358437b821d369e1314816" ]; then
      echo "[!!!] '$d/index.php' has been changed!"
      echo -e '<?php\n// Silence is golden.' > "$d/index.php"
    fi
  fi
done

if [ "${1#-}" != "$1" ]; then set -- php-fpm "$@"; fi

if [ "$1" = 'php-fpm' ]; then
  while ! nc -z mariadb 3306; do
    sleep 0.1
  done
  wp core verify-checksums || {
    echo "[!!!] Checksums of Wordpress core files are not valid."
    echo "[!!!] please run 'wp core verify-checksums' manually."
  }
  wp plugin verify-checksums --all || {
    echo "[!!!] Checksums of Wordpress plugins are not valid."
    echo "[!!!] please run 'wp plugin verify-checksums --all' manually."
  }
fi
exec "$@"

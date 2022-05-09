FROM php:8.1.5-fpm-alpine

LABEL org.label-schema.schema-version="1.0" \
      org.label-schema.description="PHP for dockerized Wordpress installation." \
      org.label-schema.name="wordpress-php" \
      org.label-schema.vcs-url="https://github.com/kugland/docker-wordpress" \
      org.opencontainers.image.source="https://github.com/kugland/docker-wordpress"

ENV PHP_EXTENSIONS="exif gd imagick mcrypt mysqli opcache zip"

# Install PHP extensions required by Wordpress.
RUN { \
  set -eux ; \
  curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions -o /usr/local/bin/install-php-extensions ; \
  IPE_GD_WITHOUTAVIF=1 /bin/sh /usr/local/bin/install-php-extensions $PHP_EXTENSIONS ; \
  rm /usr/local/bin/install-php-extensions ; \
  rm -rf /usr/src/* /usr/lib/*.a /usr/include/* ; \
}

# Add local overrides for the PHP configuration.
COPY ./local.ini /usr/local/etc/php/conf.d/99-local.ini

# Add initialization script for PHP (run on every request).
COPY ./init.php /var/www/init.php

# Set document root to /var/www.
VOLUME /var/www/html

# Change ownership of document root to www-data:www-data.
RUN chown www-data:www-data /var/www/html

RUN { \
  set -eux ; \
  sed -Ei /usr/local/etc/php-fpm.d/docker.conf \
    -e '/^access\.log = /s,/proc/self/fd/2,/var/log/php-fpm/access.log,g' \
    -e '/^error_log = /s,/proc/self/fd/2,/var/log/php-fpm/error.log,g'; \
}

# Add wp-cli.
RUN { \
  set -eux ; \
  curl -sSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp-cli.phar \
  && chmod +x /usr/local/bin/wp-cli.phar ; \
  sed -iEe '/^www-data:/{s,/sbin/nologin,/bin/sh,}' /etc/passwd* ; \
  apk add --no-cache sudo less ; \
  echo 'export PAGER="less -R"' >/home/www-data/.profile; \
  echo 'export WP_CLI_CACHE_DIR=/tmp/wp-cli-cache' >>/home/www-data/.profile; \
  echo -e '#!/bin/sh\nsudo -u www-data -i -- php /usr/local/bin/wp-cli.phar --path=/var/www/html "$@"' >/usr/local/bin/wp; \
  chmod 755 /usr/local/bin/wp ; \
}

# Add entrypoint script.
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

VOLUME [ "/var/log/php-fpm" ]
ENTRYPOINT [ "/entrypoint.sh" ]
CMD [ "php-fpm" ]

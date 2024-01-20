FROM php:8.3.2-fpm-alpine

LABEL org.opencontainers.image.title="wordpress-php" \
      org.opencontainers.image.description="php-fpm docker image for my WordPress stack" \
      org.opencontainers.image.source="https://github.com/kugland/docker-wordpress-php" \
      org.opencontainers.image.authors="André Kugland <kugland@gmail.com>"

ENV PHP_EXTENSIONS="apcu exif gd Imagick/imagick@master intl maxminddb mcrypt mysqli pdo_mysql opcache snuffleupagus zip"

# renovate: datasource=github-tags depName=mlocati/docker-php-extension-installer
ENV DOCKER_PHP_EXTENSION_INSTALLER_VERSION=2.1.76

# Install PHP extensions required by Wordpress.
RUN { \
  set -eux ; \
  curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/download/$DOCKER_PHP_EXTENSION_INSTALLER_VERSION/install-php-extensions -o /usr/local/bin/install-php-extensions ; \
  IPE_GD_WITHOUTAVIF=1 /bin/sh /usr/local/bin/install-php-extensions $PHP_EXTENSIONS ; \
  rm /usr/local/bin/install-php-extensions ; \
  rm -rf /usr/src/* /usr/lib/*.a /usr/include/* ; \
}

# renovate: datasource=github-tags depName=wp-cli/wp-cli
ENV WP_CLI_VERSION=v2.9.0

# Add wp-cli.
RUN { \
  set -eux ; \
  curl -sSL https://github.com/wp-cli/wp-cli/releases/download/$WP_CLI_VERSION/wp-cli-"$(echo "$WP_CLI_VERSION" | sed 's,^v,,g')".phar -o /usr/local/bin/wp-cli.phar \
  && chmod +x /usr/local/bin/wp-cli.phar ; \
  sed -iEe '/^www-data:/{s,/sbin/nologin,/bin/sh,}' /etc/passwd* ; \
  apk add --no-cache sudo less ; \
  echo 'export PAGER="less -R"' >/home/www-data/.profile; \
  echo 'export WP_CLI_CACHE_DIR=/tmp/wp-cli-cache' >>/home/www-data/.profile; \
  echo -e '#!/bin/sh\nsudo -u www-data -i -- php -d open_basedir=/var/www:/usr/local/bin:/tmp/wp-cli-cache:/tmp:. /usr/local/bin/wp-cli.phar --path=/var/www/html "$@"' >/usr/local/bin/wp; \
  chmod 755 /usr/local/bin/wp ; \
  mv /usr/local/etc/php/conf.d/docker-php-ext-snuffleupagus.ini /usr/local/etc/php-fpm.d/ ; \
}

# Add local overrides for the PHP configuration.
COPY ./local.ini /usr/local/etc/php/conf.d/99-local.ini

# Add Snuffleupagus rules.
COPY ./snuffleupagus.rules /usr/local/etc/php/conf.d/snuffleupagus.rules

# Add initialization script for PHP (run on every request).
COPY ./init.php /var/www/init.php

# Write logs to files, not to stdout.
RUN sed -Ei /usr/local/etc/php-fpm.d/docker.conf \
    -e '/^access\.log = /s,/proc/self/fd/2,/var/log/php-fpm/access.log,g' \
    -e '/^error_log = /s,/proc/self/fd/2,/var/log/php-fpm/error.log,g'

# Setup volumes
RUN mkdir /var/log/php-fpm /var/cache/php-opcache /var/lib/php-sessions
VOLUME [ "/var/www/html", "/var/log/php-fpm", "/var/cache/php-opcache", "/var/lib/php-sessions" ]

# Add entrypoint script.
COPY ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT [ "/entrypoint.sh" ]

# Default command
CMD [ "php-fpm" ]

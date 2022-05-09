<?php

define( 'WP_MEMORY_LIMIT', '256M' );
define( 'WP_DEBUG_DISPLAY', false );
@ini_set( 'display_errors', 0 );

if (isset($_ENV['WP_ENV']) && $_ENV['WP_ENV'] === 'development') {
  opcache_reset();
  define( 'WP_DEBUG', true );
  define( 'WP_ENVIRONMENT_TYPE', 'development' );
  define( 'FORCE_SSL_ADMIN', false );
} else {
  define( 'WP_DEBUG', false );
  define( 'WP_DEBUG_LOG', false );
  define( 'WP_ENVIRONMENT_TYPE', 'production' );
  define( 'FORCE_SSL_ADMIN', true );
}

ARG PHP_TAG=8.5-apache
FROM php:${PHP_TAG}

# Combine RUN commands to reduce layers and clean up in same layer
RUN apt-get update && apt-get install -y --no-install-recommends \
        # For memcached extension
        libmemcached-dev \
        libssl-dev \
        zlib1g-dev \
        # For GD extension
        libfreetype-dev \
        libjpeg62-turbo-dev \
        libpng-dev \
        # For imagick extension
        libmagickwand-dev \
        # For zip extension
        libzip-dev \
        # Runtime utilities
        openssl \
        zip \
        unzip \
        # LDAP
        libldap2-dev \
    # Install PECL extensions
    && pecl install memcached imagick \
    && docker-php-ext-enable memcached imagick \
    # Configure and install GD
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    # Install bundled extensions
    && docker-php-ext-install -j$(nproc) \
        gd \
        mysqli \
        pdo_mysql \
        calendar \
        exif \
        gettext \
        iconv \
        zip \
        sockets \
        ldap \
    # Enable Apache modules
    && a2enmod headers expires rewrite proxy proxy_http proxy_wstunnel remoteip \
    # Disable unnecessary Apache modules
    && a2dismod -f autoindex status \
    # Cleanup
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    # Remove default index
    && rm -rf /var/www/html/*

### --- Harden Apache Configuration ---
ARG APACHE_CONF_FILE=/etc/apache2/apache2.conf
RUN sed -i -e '/^ServerTokens/d' -e '/^ServerSignature/d' "${APACHE_CONF_FILE}" && \
    printf '\n# Security Hardening\n\
ServerTokens Prod\n\
ServerSignature Off\n\
TraceEnable Off\n\
' >> "${APACHE_CONF_FILE}" && \
    # Disable directory listing
    sed -i 's/Options Indexes FollowSymLinks/Options -Indexes +FollowSymLinks/g' "${APACHE_CONF_FILE}"

### --- Security Headers ---
RUN printf '<IfModule mod_headers.c>\n\
    Header always set X-Content-Type-Options "nosniff"\n\
    Header always set X-Frame-Options "SAMEORIGIN"\n\
    Header always set X-XSS-Protection "1; mode=block"\n\
    Header always set Referrer-Policy "strict-origin-when-cross-origin"\n\
    Header always unset X-Powered-By\n\
</IfModule>\n' > /etc/apache2/conf-available/security-headers.conf \
    && a2enconf security-headers
### --- Harden PHP Configuration ---
RUN sed -i 's/expose_php = On/expose_php = Off/g' \
        /usr/local/etc/php/php.ini-development \
        /usr/local/etc/php/php.ini-production \
    && cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini

### --- PHP Security Settings ---
RUN printf '[PHP]\n\
; disable_functions=passthru,shell_exec,system,proc_open,popen,pcntl_exec\n\
max_execution_time=30\n\
max_input_time=60\n\
memory_limit=384M\n\
post_max_size=16M\n\
upload_max_filesize=8M\n\
max_file_uploads=5\n\
session.cookie_httponly=1\n\
session.cookie_secure=1\n\
session.use_strict_mode=1\n\
session.cookie_samesite=Strict\n\
display_errors=Off\n\
display_startup_errors=Off\n\
log_errors=On\n\
allow_url_include=Off\n\
' > /usr/local/etc/php/conf.d/security.ini

### --- Configure OPcache ---
RUN printf '[opcache]\n\
opcache.enable=1\n\
opcache.enable_cli=1\n\
opcache.memory_consumption=384\n\
opcache.interned_strings_buffer=64\n\
opcache.max_accelerated_files=10000\n\
opcache.fast_shutdown=1\n\
opcache.huge_code_pages=1\n\
opcache.validate_timestamps=0\n\
opcache.revalidate_freq=0\n' > /usr/local/etc/php/conf.d/opcache-prod.ini

ARG PHP_TAG
LABEL Author="tracyhatemice"
LABEL Version="php:${PHP_TAG}"
LABEL Description="PHP Apache environment (hardened)"

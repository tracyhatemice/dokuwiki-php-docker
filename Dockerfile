ARG PHP_TAG=8.5-apache
FROM php:${PHP_TAG}

# Combine RUN commands to reduce layers and clean up in same layer
# PIE (successor to PECL) is bind-mounted for this step only, so it is not left in the image
RUN --mount=type=bind,from=ghcr.io/php/pie:1-bin,source=/pie,target=/usr/local/bin/pie \
    apt-get update \
    # Runtime packages (kept in the final image)
    && apt-get install -y --no-install-recommends \
        # ImageMagick CLI (magick/convert), e.g. for DokuWiki's im_convert
        imagemagick \
        # Runtime utilities (unzip is also used by PIE to extract sources)
        openssl \
        zip \
        unzip \
    # Build-only packages (everything installed after this mark is purged below)
    && savedAptMark="$(apt-mark showmanual)" \
    && apt-get install -y --no-install-recommends \
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
        # For intl extension
        libicu-dev \
        # For zip extension
        libzip-dev \
        # LDAP
        libldap2-dev \
    # Install extensions via PIE (enabled automatically through docker-php-ext-enable);
    # build tools come from the base image's PHPIZE_DEPS, so skip PIE's libtoolize check
    && pie install --no-cache --no-build-tools-check \
        php-memcached/php-memcached \
        imagick/imagick \
    # Configure and install GD
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    # Install bundled extensions
    && docker-php-ext-install -j$(nproc) \
        gd \
        intl \
        mysqli \
        pdo_mysql \
        calendar \
        exif \
        gettext \
        iconv \
        zip \
        sockets \
        ldap \
    # Keep only the runtime libraries the compiled extensions link against, so the
    # purge below removes the -dev packages (pattern from the official php image docs)
    && apt-mark auto '.*' > /dev/null \
    && apt-mark manual $savedAptMark \
    && ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
        | sort -u \
        | xargs -r dpkg-query --search \
        | cut -d: -f1 \
        | sort -u \
        | xargs -r apt-mark manual \
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

### --- Apache Worker Limits ---
# mod_php handles one request per prefork worker, each allowed up to memory_limit.
# Default sized for a 2 vCPU / 2GB host; override at runtime (ServerLimit follows it).
ENV APACHE_MAX_REQUEST_WORKERS=20
RUN printf '<IfModule mpm_prefork_module>\n\
    ServerLimit             ${APACHE_MAX_REQUEST_WORKERS}\n\
    StartServers            5\n\
    MinSpareServers         5\n\
    MaxSpareServers         10\n\
    MaxRequestWorkers       ${APACHE_MAX_REQUEST_WORKERS}\n\
    MaxConnectionsPerChild  1000\n\
</IfModule>\n' > /etc/apache2/mods-available/mpm_prefork.conf \
    # Idle keep-alive connections (e.g. a reverse proxy's connection pool) would each pin
    # a prefork worker; close after every response instead
    && sed -i 's/^KeepAlive On$/KeepAlive Off/' /etc/apache2/apache2.conf \
    && grep -qx 'KeepAlive Off' /etc/apache2/apache2.conf

### --- Security Headers ---
RUN printf '<IfModule mod_headers.c>\n\
    Header always set X-Content-Type-Options "nosniff"\n\
    Header always set X-Frame-Options "SAMEORIGIN"\n\
    Header always set Referrer-Policy "strict-origin-when-cross-origin"\n\
    Header always unset X-Powered-By\n\
</IfModule>\n' > /etc/apache2/conf-available/security-headers.conf \
    && a2enconf security-headers

### --- ImageMagick Security Policy ---
# Allow only the web image formats DokuWiki resizes; no helper programs, filters,
# network or @file reads, and tighter resource limits than Debian's defaults
RUN printf '<policymap>\n\
  <policy domain="resource" name="memory" value="256MiB"/>\n\
  <policy domain="resource" name="map" value="512MiB"/>\n\
  <policy domain="resource" name="disk" value="1GiB"/>\n\
  <policy domain="resource" name="area" value="128MP"/>\n\
  <policy domain="resource" name="width" value="16KP"/>\n\
  <policy domain="resource" name="height" value="16KP"/>\n\
  <policy domain="resource" name="time" value="60"/>\n\
  <policy domain="delegate" rights="none" pattern="*"/>\n\
  <policy domain="filter" rights="none" pattern="*"/>\n\
  <policy domain="path" rights="none" pattern="@*"/>\n\
  <policy domain="coder" rights="none" pattern="*"/>\n\
  <policy domain="coder" rights="read|write" pattern="{GIF,JPEG,JPG,PNG,WEBP}"/>\n\
</policymap>\n' > /etc/ImageMagick-7/policy.xml

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
memory_limit=128M\n\
post_max_size=16M\n\
upload_max_filesize=8M\n\
max_file_uploads=5\n\
session.use_only_cookies=1\n\
session.cookie_httponly=1\n\
session.cookie_secure=1\n\
session.use_strict_mode=1\n\
session.use_trans_sid=0\n\
session.cookie_samesite=Strict\n\
display_errors=Off\n\
display_startup_errors=Off\n\
log_errors=On\n\
allow_url_include=Off\n\
' > /usr/local/etc/php/conf.d/security.ini

### --- Configure OPcache ---
RUN printf '[opcache]\n\
opcache.enable=1\n\
opcache.memory_consumption=128\n\
opcache.interned_strings_buffer=32\n\
opcache.max_accelerated_files=10000\n\
opcache.validate_timestamps=0\n\
opcache.revalidate_freq=0\n\
\n\
[PHP]\n\
; Cache resolved file paths longer (DokuWiki is file-based)\n\
realpath_cache_ttl=600\n' > /usr/local/etc/php/conf.d/opcache-prod.ini

ARG PHP_TAG
LABEL Author="tracyhatemice"
LABEL Version="php:${PHP_TAG}"
LABEL Description="PHP Apache environment (hardened)"

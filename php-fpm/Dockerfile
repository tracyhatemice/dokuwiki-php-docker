ARG PHP_TAG=8.5-fpm
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
    # Cleanup
    && apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
    # Remove default index
    && rm -rf /var/www/html/*

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
; Map PHP-FPM'"'"'s own code into huge pages (fewer TLB misses); needs the host'"'"'s\n\
; transparent huge pages in "madvise" or "always" mode, otherwise it is a no-op\n\
opcache.huge_code_pages=1\n\
\n\
[PHP]\n\
; Cache resolved file paths longer (DokuWiki is file-based)\n\
realpath_cache_ttl=600\n' > /usr/local/etc/php/conf.d/opcache-prod.ini

### --- PHP-FPM Pool ---
# Listens on a Unix socket that the web server container reaches through a shared volume.
# Default sized for a 2 vCPU / 2GB host; override PHP_FPM_MAX_CHILDREN at runtime (minimum 6).
ENV PHP_FPM_MAX_CHILDREN=20
RUN printf '[www]\n\
listen = /run/php-fpm/php-fpm.sock\n\
listen.mode = 0660\n\
pm = dynamic\n\
pm.max_children = ${PHP_FPM_MAX_CHILDREN}\n\
pm.start_servers = 4\n\
pm.min_spare_servers = 2\n\
pm.max_spare_servers = 6\n\
pm.max_requests = 1000\n\
; Hard wall-clock limit per request (max_execution_time only counts CPU time)\n\
request_terminate_timeout = 60s\n\
; The web server already logs every request\n\
access.log = /dev/null\n' > /usr/local/etc/php-fpm.d/zz-dokuwiki.conf \
    # The master runs as www-data (see USER below), so there is no user to switch to
    && sed -i -e '/^user = /d' -e '/^group = /d' /usr/local/etc/php-fpm.d/www.conf \
    && mkdir -p /run/php-fpm \
    && chown www-data:www-data /run/php-fpm

USER www-data

ARG PHP_TAG
LABEL Author="tracyhatemice"
LABEL Version="php:${PHP_TAG}"
LABEL Description="PHP-FPM for DokuWiki (hardened)"

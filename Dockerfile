# Ported from docker-library/php 9dac3d048ebdcdb3b6a27350b7572ddee58c70df, 8.5/trixie/apache/Dockerfile.
# Keep in step with upstream by hand; scripts/php-pin.sh rewrites only the PHP_VERSION/PHP_URL/PHP_SHA256 lines.
# Changed from upstream: the signature check uses docker-php/verify-php-signature with php.net's keyring, not a keyserver.

FROM debian:trixie-slim AS php-base

# prevent Debian's PHP packages from being installed
# https://github.com/docker-library/php/pull/542
RUN set -eux; \
	{ \
		echo 'Package: php*'; \
		echo 'Pin: release *'; \
		echo 'Pin-Priority: -1'; \
	} > /etc/apt/preferences.d/no-debian-php

# dependencies required for running "phpize"
# (see persistent deps below)
ENV PHPIZE_DEPS \
		autoconf \
		dpkg-dev \
		file \
		g++ \
		gcc \
		libc-dev \
		make \
		pkg-config \
		re2c

# persistent / runtime deps
RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		xz-utils \
	; \
	apt-get dist-clean

ENV PHP_INI_DIR /usr/local/etc/php
RUN set -eux; \
	mkdir -p "$PHP_INI_DIR/conf.d"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
	[ ! -d /var/www/html ]; \
	mkdir -p /var/www/html; \
	chown www-data:www-data /var/www/html; \
	chmod 1777 /var/www/html

ENV APACHE_CONFDIR /etc/apache2
ENV APACHE_ENVVARS $APACHE_CONFDIR/envvars

RUN set -eux; \
	apt-get update; \
	apt-get install -y --no-install-recommends apache2; \
	apt-get dist-clean; \
	\
# generically convert lines like
#   export APACHE_RUN_USER=www-data
# into
#   : ${APACHE_RUN_USER:=www-data}
#   export APACHE_RUN_USER
# so that they can be overridden at runtime ("-e APACHE_RUN_USER=...")
	sed -ri 's/^export ([^=]+)=(.*)$/: ${\1:=\2}\nexport \1/' "$APACHE_ENVVARS"; \
	\
# setup directories and permissions
	. "$APACHE_ENVVARS"; \
	for dir in \
		"$APACHE_LOCK_DIR" \
		"$APACHE_RUN_DIR" \
		"$APACHE_LOG_DIR" \
# https://salsa.debian.org/apache-team/apache2/-/commit/b97ca8714890ead1ba6c095699dde752e8433205
		"$APACHE_RUN_DIR/socks" \
	; do \
		rm -rvf "$dir"; \
		mkdir -p "$dir"; \
		chown "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$dir"; \
# allow running as an arbitrary user (https://github.com/docker-library/php/issues/743)
		chmod 1777 "$dir"; \
	done; \
	\
# delete the "index.html" that installing Apache drops in here
	rm -rvf /var/www/html/*; \
	\
# logs should go to stdout / stderr
	ln -sfT /dev/stderr "$APACHE_LOG_DIR/error.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/access.log"; \
	ln -sfT /dev/stdout "$APACHE_LOG_DIR/other_vhosts_access.log"; \
	chown -R --no-dereference "$APACHE_RUN_USER:$APACHE_RUN_GROUP" "$APACHE_LOG_DIR"

# Apache + PHP requires preforking Apache for best results
RUN a2dismod mpm_event && a2enmod mpm_prefork

# PHP files should be handled by PHP, and should be preferred over any other file type
RUN { \
		echo '<FilesMatch \.php$>'; \
		echo '\tSetHandler application/x-httpd-php'; \
		echo '</FilesMatch>'; \
		echo; \
		echo 'DirectoryIndex disabled'; \
		echo 'DirectoryIndex index.php index.html'; \
		echo; \
		echo '<Directory /var/www/>'; \
		echo '\tOptions -Indexes'; \
		echo '\tAllowOverride All'; \
		echo '</Directory>'; \
	} | tee "$APACHE_CONFDIR/conf-available/docker-php.conf" \
	&& a2enconf docker-php

# Apply stack smash protection to functions using local buffers and alloca()
# Make PHP's main executable position-independent (improves ASLR security mechanism, and has no performance impact on x86_64)
# Enable optimization (-O2)
# Enable linker optimization (this sorts the hash buckets to improve cache locality, and is non-default)
# https://github.com/docker-library/php/issues/272
# -D_LARGEFILE_SOURCE and -D_FILE_OFFSET_BITS=64 (https://www.php.net/manual/en/intro.filesystem.php)
ENV PHP_CFLAGS="-fstack-protector-strong -fpic -fpie -O2 -D_LARGEFILE_SOURCE -D_FILE_OFFSET_BITS=64"
ENV PHP_CPPFLAGS="$PHP_CFLAGS"
ENV PHP_LDFLAGS="-Wl,-O1 -pie"

ENV GPG_KEYS 1198C0117593497A5EC5C199286AF1F9897469DC 49D9AF6BC72A80D6691719C8AA23F5BE9C7097D4 D95C03BC702BE9515344AE3374E44BC9067701A5

ENV PHP_VERSION 8.5.12
ENV PHP_URL="https://www.php.net/distributions/php-8.5.12.tar.xz" PHP_ASC_URL="https://www.php.net/distributions/php-8.5.12.tar.xz.asc"
ENV PHP_SHA256="08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209"

RUN --mount=type=bind,source=docker-php/verify-php-signature,target=/usr/local/bin/verify-php-signature \
	set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends gnupg; \
	apt-get dist-clean; \
	\
	mkdir -p /usr/src; \
	cd /usr/src; \
	\
	curl -fsSL -o php.tar.xz "$PHP_URL"; \
	\
	if [ -n "$PHP_SHA256" ]; then \
		echo "$PHP_SHA256 *php.tar.xz" | sha256sum -c -; \
	fi; \
	\
	curl -fsSL -o php.tar.xz.asc "$PHP_ASC_URL"; \
# changed from upstream: check against php.net's keyring (over HTTPS) instead of a keyserver lookup;
# only a signature from one of the pinned GPG_KEYS fingerprints is accepted
	curl -fsSL -o php-keyring.gpg https://www.php.net/distributions/php-keyring.gpg; \
	verify-php-signature php.tar.xz php.tar.xz.asc php-keyring.gpg; \
	rm php-keyring.gpg; \
	\
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

COPY docker-php/docker-php-source /usr/local/bin/

RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		apache2-dev \
		libargon2-dev \
		libcurl4-openssl-dev \
		libonig-dev \
		libreadline-dev \
		libsodium-dev \
		libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		zlib1g-dev \
	; \
	\
	export \
		CFLAGS="$PHP_CFLAGS" \
		CPPFLAGS="$PHP_CPPFLAGS" \
		LDFLAGS="$PHP_LDFLAGS" \
# https://github.com/php/php-src/blob/d6299206dd828382753453befd1b915491b741c6/configure.ac#L1496-L1511
		PHP_BUILD_PROVIDER='https://github.com/docker-library/php' \
		PHP_UNAME='Linux - Docker' \
	; \
	docker-php-source extract; \
	cd /usr/src/php; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
# https://bugs.php.net/bug.php?id=74125
	if [ ! -d /usr/include/curl ]; then \
		ln -sT "/usr/include/$debMultiarch/curl" /usr/local/include/curl; \
	fi; \
	case "$gnuArch" in \
		'i686-linux-'*) \
			# php zend jit assumes SSE registers, xmm0-7, are available (and "Pentium4"/SSE2 is a reasonable baseline)
			# https://github.com/php/php-src/pull/22832
			# so, allow it and use SSE/SSE2 floating-point unit instead of the legacy stack
			export \
				CFLAGS="$CFLAGS -msse2 -mfpmath=sse" \
				CPPFLAGS="$CPPFLAGS -msse2 -mfpmath=sse" \
			; \
			;; \
	esac; \
	test "$PHP_INI_DIR" != "${PHP_INI_DIR%/php}"; \
	./configure \
		--build="$gnuArch" \
		--sysconfdir="${PHP_INI_DIR%/php}" \
		--with-config-file-path="$PHP_INI_DIR" \
		--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
		\
# make sure invalid --configure-flags are fatal errors instead of just warnings
		--enable-option-checking=fatal \
		\
# https://github.com/docker-library/php/issues/439
		--with-mhash \
		\
# https://github.com/docker-library/php/issues/822
		--with-pic \
		\
# --enable-mbstring is included here because otherwise there's no way to get pecl to use it properly (see https://github.com/docker-library/php/issues/195)
		--enable-mbstring \
# --enable-mysqlnd is included here because it's harder to compile after the fact than extensions are (since it's a plugin for several extensions, not an extension in itself)
		--enable-mysqlnd \
# https://wiki.php.net/rfc/argon2_password_hash
		--with-password-argon2 \
# https://wiki.php.net/rfc/libsodium
		--with-sodium=shared \
# always build against system sqlite3 (https://github.com/php/php-src/commit/6083a387a81dbbd66d6316a3a12a63f06d5f7109)
		--with-pdo-sqlite=/usr \
		--with-sqlite3=/usr \
		\
		--with-curl \
		--with-iconv \
		--with-openssl \
		--with-readline \
		--with-zlib \
		\
# https://github.com/bwoebi/phpdbg-docs/issues/1#issuecomment-163872806 ("phpdbg is primarily a CLI debugger, and is not suitable for debugging an fpm stack.")
		--disable-phpdbg \
		\
# in PHP 7.4+, the pecl/pear installers are officially deprecated (requiring an explicit "--with-pear")
		--with-pear \
		\
		--with-libdir="lib/$debMultiarch" \
		\
		--disable-cgi \
		\
		--with-apxs2 \
	; \
	make -j "$(nproc)"; \
	find -type f -name '*.a' -delete; \
	make install; \
	find \
		/usr/local \
		-type f \
		-perm '/0111' \
		-exec sh -euxc ' \
			strip --strip-all "$@" || : \
		' -- '{}' + \
	; \
	make clean; \
	\
# https://github.com/docker-library/php/issues/692 (copy default example "php.ini" files somewhere easily discoverable)
	cp -v php.ini-* "$PHP_INI_DIR/"; \
	\
	cd /; \
	docker-php-source delete; \
	\
# reset apt-mark's "manual" list so that "purge --auto-remove" will remove all build dependencies
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	find /usr/local -type f -executable -exec ldd '{}' ';' \
		| awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) { next }; gsub("^/(usr/)?", "", so); printf "*%s\n", so }' \
		| sort -u \
		| xargs -rt dpkg-query --search \
# https://manpages.debian.org/trixie/dpkg/dpkg-query.1.en.html#S (we ignore diversions and it'll be really unusual for more than one package to provide any given .so file)
		| awk 'sub(":$", "", $1) { print $1 }' \
		| sort -u \
		| xargs -r apt-mark manual \
	; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	apt-get dist-clean; \
	\
# update pecl channel definitions https://github.com/docker-library/php/issues/443
	pecl update-channels; \
	rm -rf /tmp/pear ~/.pearrc; \
	\
# smoke test
	php --version

COPY docker-php/docker-php-ext-* docker-php/docker-php-entrypoint /usr/local/bin/

# sodium was built as a shared module (so that it can be replaced later if so desired), so let's enable it too (https://github.com/docker-library/php/issues/598)
RUN docker-php-ext-enable sodium

ENTRYPOINT ["docker-php-entrypoint"]
# https://httpd.apache.org/docs/2.4/stopping.html#gracefulstop
STOPSIGNAL SIGWINCH

COPY docker-php/apache2-foreground /usr/local/bin/
WORKDIR /var/www/html

EXPOSE 80
CMD ["apache2-foreground"]

FROM php-base

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
session.upload_progress.enabled=0\n\
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

LABEL Author="tracyhatemice"
LABEL Version="php:${PHP_VERSION}"
LABEL Description="PHP Apache environment (hardened)"

ARG HTTPD_TAG=2.4
FROM httpd:${HTTPD_TAG}

# Modules: FastCGI proxying to PHP-FPM, rewrite for DokuWiki's nice URLs, remoteip for
# client IPs behind a reverse proxy; drop directory listings and the status page.
# Listen on 8080 so Apache runs without root; log requests in the combined format.
RUN sed -i \
        -e 's/^#\(LoadModule proxy_module \)/\1/' \
        -e 's/^#\(LoadModule proxy_fcgi_module \)/\1/' \
        -e 's/^#\(LoadModule rewrite_module \)/\1/' \
        -e 's/^#\(LoadModule remoteip_module \)/\1/' \
        -e 's/^\(LoadModule autoindex_module \)/#\1/' \
        -e 's/^\(LoadModule status_module \)/#\1/' \
        -e 's/^Listen 80$/Listen 8080/' \
        -e 's|^\([[:space:]]*CustomLog /proc/self/fd/1\) common$|\1 combined|' \
        /usr/local/apache2/conf/httpd.conf \
    && grep -qx 'Listen 8080' /usr/local/apache2/conf/httpd.conf \
    && grep -q 'CustomLog /proc/self/fd/1 combined' /usr/local/apache2/conf/httpd.conf \
    # DokuWiki config, then optional site-specific overrides mounted into conf/custom/
    && printf 'Include conf/extra/dokuwiki.conf\nIncludeOptional conf/custom/*.conf\n' >> /usr/local/apache2/conf/httpd.conf \
    && mkdir -p /usr/local/apache2/conf/custom /var/www/html /run/php-fpm \
    && chown www-data:www-data /run/php-fpm

# Reverse proxy addresses allowed to set X-Forwarded-For (space-separated IPs/CIDRs);
# defaults to all private ranges, narrow it to your proxy's Docker network if you like
ENV APACHE_TRUSTED_PROXIES="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7"

COPY dokuwiki.conf /usr/local/apache2/conf/extra/dokuwiki.conf

USER www-data
EXPOSE 8080

ARG HTTPD_TAG
LABEL Author="tracyhatemice"
LABEL Version="httpd:${HTTPD_TAG}"
LABEL Description="Apache (event MPM) for DokuWiki, PHP via PHP-FPM (hardened)"

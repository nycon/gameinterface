FROM php:8.4-apache-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        git unzip libpq-dev libzip-dev libicu-dev \
    && docker-php-ext-install pdo_pgsql pcntl bcmath intl zip \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && a2enmod rewrite headers \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV APACHE_DOCUMENT_ROOT=/var/www/html/public
RUN sed -ri -e 's!/var/www/html!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/sites-available/*.conf \
    && sed -ri -e 's!/var/www/!${APACHE_DOCUMENT_ROOT}!g' /etc/apache2/apache2.conf /etc/apache2/conf-available/*.conf \
    && printf '%s\n' \
        '<Directory /var/www/html/public>' \
        '    AllowOverride All' \
        '    Require all granted' \
        '</Directory>' \
        > /etc/apache2/conf-available/gamepanel-laravel.conf \
    && a2enconf gamepanel-laravel

WORKDIR /var/www/html

COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist

COPY . .
RUN rm -f bootstrap/cache/packages.php bootstrap/cache/services.php \
    && composer dump-autoload --optimize \
    && php artisan package:discover --ansi --no-interaction \
    && chown -R www-data:www-data storage bootstrap/cache \
    && chmod -R ug+rwx storage bootstrap/cache

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8000
# Apache normalerweise 80 — wir mappen auf 8000 für Compose-Kompatibilität
RUN sed -i 's/80/8000/g' /etc/apache2/ports.conf /etc/apache2/sites-available/000-default.conf

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["apache2-foreground"]

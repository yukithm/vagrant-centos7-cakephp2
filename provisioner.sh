#!/bin/sh

#--------------------------------------
# Base
#--------------------------------------

# locale and timezone
localectl set-locale LANG=en_US.utf8
timedatectl set-timezone Asia/Tokyo

# man
yum -y install man man-pages man-pages-ja

# dkms
yum -y install epel-release
yum -y install dkms

# update all
yum -y update

# chrony
yum -y install chrony
systemctl enable chronyd
systemctl start chronyd


#--------------------------------------
# Database
#--------------------------------------

MYSQL_ROOT_PASSWORD=vagrant

# mariadb (mysql)
yum -y install mariadb-server
cp /usr/share/mysql/my-medium.cnf /etc/my.cnf.d
sed -i -e '/^\[client\]$/a\default-character-set = utf8mb4' /etc/my.cnf.d/my-medium.cnf
sed -i -e '/^\[mysqld\]$/a\character-set-server = utf8mb4' /etc/my.cnf.d/my-medium.cnf
systemctl enable mariadb
systemctl start mariadb

# same as mysql_secure_installation
/usr/bin/mysql -D mysql -e "UPDATE mysql.user SET Password=PASSWORD('${MYSQL_ROOT_PASSWORD}') WHERE User='root';"
/usr/bin/mysql -D mysql -e "DELETE FROM mysql.user WHERE User='';"
/usr/bin/mysql -D mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
/usr/bin/mysql -D mysql -e "DROP DATABASE test;"
/usr/bin/mysql -D mysql -e "DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';"
/usr/bin/mysql -D mysql -e "FLUSH PRIVILEGES;"


#--------------------------------------
# PHP and Apache
#--------------------------------------

# php and apache
yum -y install php php-mbstring php-mcrypt php-pdo php-mysqlnd
cp /etc/php.ini{,.orig}
sed -i -e 's/^display_errors = Off/display_errors = On/' /etc/php.ini
sed -i -e 's/^;date.timezone =/date.timezone = Asia\/Tokyo/' /etc/php.ini
cp /etc/php.d/mbstring.ini{,.orig}
/bin/sh -c 'echo "mbstring.language = Japanese" >>/etc/php.d/mbstring.ini'
/bin/sh -c 'echo "mbstring.internal_encoding = UTF-8" >>/etc/php.d/mbstring.ini'
systemctl enable httpd
systemctl start httpd

# composer
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

#--------------------------------------
# phpMyAdmin
#--------------------------------------

yum -y install phpmyadmin
cp /etc/httpd/conf.d/phpMyAdmin.conf{,.orig}
sed -i -e '/<\/RequireAny>/i\       Require all granted' /etc/httpd/conf.d/phpMyAdmin.conf
# systemctl restart httpd

#--------------------------------------
# CakePHP
#--------------------------------------

CAKEPHP_DB_NAME=cakephp
CAKEPHP_DB_USER=cakephp
CAKEPHP_DB_PASS=cakephp

# database
cat <<_SQL_ | /usr/bin/mysql -u root -p${MYSQL_ROOT_PASSWORD}
CREATE DATABASE ${CAKEPHP_DB_NAME} CHARACTER SET utf8mb4;
CREATE DATABASE test_${CAKEPHP_DB_NAME} CHARACTER SET utf8mb4;
GRANT ALL ON ${CAKEPHP_DB_NAME}.* TO ${CAKEPHP_DB_USER}@localhost IDENTIFIED BY '${CAKEPHP_DB_PASS}';
GRANT ALL ON test_${CAKEPHP_DB_NAME}.* TO ${CAKEPHP_DB_USER}@localhost IDENTIFIED BY '${CAKEPHP_DB_PASS}';
FLUSH PRIVILEGES;
_SQL_

# cakephp
(cd /app && /usr/local/bin/composer install && yes | Vendor/bin/cake bake project --empty .)
sed -e '/DATABASE_CONFIG/,/^}/d' /app/Config/database.php.default >/app/Config/database.php
cat <<_DB_ >>/app/Config/database.php
class DATABASE_CONFIG {

    public \$default = array(
        'datasource' => 'Database/Mysql',
        'persistent' => false,
        'host' => 'localhost',
        'login' => '${CAKEPHP_DB_USER}',
        'password' => '${CAKEPHP_DB_PASS}',
        'database' => '${CAKEPHP_DB_NAME}',
        'prefix' => '',
        'encoding' => 'utf8mb4',
    );

    public \$test = array(
        'datasource' => 'Database/Mysql',
        'persistent' => false,
        'host' => 'localhost',
        'login' => '${CAKEPHP_DB_USER}',
        'password' => '${CAKEPHP_DB_PASS}',
        'database' => 'test_${CAKEPHP_DB_NAME}',
        'prefix' => '',
        'encoding' => 'utf8mb4',
    );
}
_DB_

# debug_kit plugin
yum -y install patch
cp /app/Config/bootstrap.php{,.orig}
cat <<'_PATCH_' | (cd /app && patch -p1)
--- a/Config/bootstrap.php       2015-07-02 03:44:01.000000000 +0900
+++ b/Config/bootstrap.php       2015-07-02 23:21:22.000000000 +0900
@@ -13,6 +13,11 @@
  * @since         CakePHP(tm) v 0.10.8.2117
  */

+require APP . 'Vendor/autoload.php';
+
+spl_autoload_unregister(array('App', 'load'));
+spl_autoload_register(array('App', 'load'), true, true);
+
 // Setup a 'default' cache configuration for use in the application.
 Cache::config('default', array('engine' => 'File'));

@@ -60,6 +65,7 @@
  * CakePlugin::load('DebugKit'); //Loads a single plugin named DebugKit
  *
  */
+CakePlugin::loadAll();

 /**
  * You can attach event listeners to the request lifecycle as Dispatcher Filter . By default CakePHP bundles two filters:
_PATCH_

# apache
cat <<'_CONF_' >/etc/httpd/conf.d/vhost.conf
<VirtualHost *:80>
    DocumentRoot /app/webroot
    EnableSendfile off

    <Directory "/app/webroot">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
_CONF_
usermod -aG vagrant apache
systemctl restart httpd


#--------------------------------------
# Miscellaneous
#--------------------------------------

# favorite softwares
yum -y install zsh vim git screen tmux tree


#--------------------------------------
# Cleanup
#--------------------------------------

# clean yum cache
yum clean all

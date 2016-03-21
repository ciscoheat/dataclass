#!/usr/bin/env bash

echo "=== Starting provision script..."

cd /vagrant

echo "=== Adding 'cd /vagrant' to .profile"
cat >> /home/vagrant/.profile <<EOL

cd /vagrant
EOL

echo "=== Updating apt..."
apt-get update >/dev/null 2>&1
# Used in many dependencies:
apt-get install python-software-properties -y

mkdir www
chown vagrant:vagrant www

echo "=== Installing Apache..."
apt-get install -y apache2

# Enable mod_rewrite, allow .htaccess and fix a virtualbox bug according to
# https://github.com/mitchellh/vagrant/issues/351#issuecomment-1339640
a2enmod rewrite
sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/sites-enabled/000-default
echo EnableSendFile Off > /etc/apache2/conf.d/virtualbox-bugfix

# Link to www dir
rm -rf /var/www
ln -fs /vagrant/www /var/www

echo "=== Installing curl..."
apt-get install -y curl

echo "=== Installing PHP..."
apt-get install -y php5 php5-gd php5-mysql php5-curl php5-cli php5-sqlite php5-xdebug php-apc

cat > /etc/php5/conf.d/vagrant.ini <<EOL
display_errors = On
html_errors = On
xdebug.max_nesting_level=10000
EOL

echo "=== Installing PHP utilities (Composer)..."
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin

echo "=== Installing PHP utilities (phing)..."
wget -q -O /usr/local/bin/phing.phar http://www.phing.info/get/phing-latest.phar && chmod 755 /usr/local/bin/phing.phar

echo "=== Installing Mysql..."
export DEBIAN_FRONTEND=noninteractive
apt-get -q -y install mysql-server mysql-client

echo "=== Creating Mysql DB (test)..."
mysql -u root -e "create database test"

echo "=== Restarting Apache..."
service apache2 restart

echo "=== Installing Haxe 3.2.1..."
wget -q http://www.openfl.org/builds/haxe/haxe-3.2.1-linux-installer.tar.gz -O - | tar -xv
sh install-haxe.sh -y >/dev/null 2>&1
rm -f install-haxe.sh

echo /usr/lib/haxe/lib/ | haxelib setup
echo /usr/lib/haxe/lib/ > /home/vagrant/.haxelib
chown vagrant:vagrant /home/vagrant/.haxelib

echo "=== Installing mod_neko for Apache..."

cat > /etc/apache2/conf.d/neko <<EOL
LoadModule neko_module /usr/lib/neko/mod_neko2.ndll
AddHandler neko-handler .n
DirectoryIndex index.n
EOL

mkdir /vagrant/src

cat > /vagrant/src/Index.hx <<EOL
class Index {
    static function main() {
        trace("Hello World !");
    }
}
EOL

cat > /vagrant/src/build.hxml <<EOL
-neko ../www/index.n
-main Index
EOL

chown -R vagrant:vagrant src
su vagrant -c 'cd /vagrant/src && haxe build.hxml'

service apache2 restart

echo "=== Installing Haxe targets:"

echo "=== Installing C++..."
apt-get install -y gcc-multilib g++-multilib
haxelib install hxcpp >/dev/null 2>&1

echo "=== Installing C#..."
apt-get install -y mono-devel mono-mcs
haxelib install hxcs >/dev/null 2>&1

echo "=== Installing Java..."
haxelib install hxjava >/dev/null 2>&1

echo "=== Installing PHP..."
apt-get install -y php5-cli

echo "=== Installing Flash (xvfb)..."
apt-get install -y xvfb

echo "=== Installing Node.js..."
add-apt-repository ppa:chris-lea/node.js -y
apt-get update
apt-get install nodejs -y
# npm config set spin=false

echo "=== Installing Phantomjs (js testing)..."
npm install -g phantomjs-prebuilt

echo "=== Installing Python 3.4..."
add-apt-repository ppa:fkrull/deadsnakes -y
apt-get update
apt-get install python3.4 -y
ln -s /usr/bin/python3.4 /usr/bin/python3

echo "=== Installing Java 8 JDK (openjdk)..."
add-apt-repository ppa:openjdk-r/ppa -y
apt-get update
apt-get install openjdk-8-jdk -y

echo "If you have several java versions and want to switch:"
echo "sudo update-alternatives --config java"
echo "sudo update-alternatives --config javac"
echo ""
echo "Current java version:"
java -version

sed -i 's/precise64/dataclass/g' /etc/hostname /etc/hosts

echo "=== Provision script finished!"
echo "Change timezone: sudo dpkg-reconfigure tzdata"
echo "Change hostname: sudo pico /etc/hostname && sudo pico /etc/hosts"
echo ""
echo "If you have renamed the vm with '-n', execute 'vagrant reload' to finish the process."

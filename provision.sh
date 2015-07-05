#!/usr/bin/env bash

echo "=== Starting provision script..."

cd /vagrant

echo "=== Adding 'cd /vagrant' to .profile"
cat >> /home/vagrant/.profile <<EOL

cd /vagrant
EOL

echo "=== Updating apt..."
apt-get update >/dev/null 2>&1

echo "=== Installing Node.js..."
apt-get install python-software-properties -y
add-apt-repository ppa:chris-lea/node.js -y
apt-get update
apt-get install nodejs -y
# npm config set spin=false

echo "=== Installing Phantomjs (js testing)..."
npm install -g phantomjs

echo "=== Installing Haxe 3.2.0..."
wget -q http://www.openfl.org/builds/haxe/haxe-3.2.0-linux-installer.tar.gz -O - | tar -xz
sh install-haxe.sh -y >/dev/null 2>&1
rm -f install-haxe.sh

echo /usr/lib/haxe/lib/ | haxelib setup
echo /usr/lib/haxe/lib/ > /home/vagrant/.haxelib
chown vagrant:vagrant /home/vagrant/.haxelib

echo "=== Installing Haxe targets:"

echo "=== Installing C++..."
apt-get install -y gcc-multilib g++-multilib
haxelib install hxcpp >/dev/null 2>&1

echo "=== Installing C#..."
apt-get install -y mono-devel
haxelib install hxcs >/dev/null 2>&1

echo "=== Installing Java..."
apt-get install -y default-jdk
haxelib install hxjava >/dev/null 2>&1

sed -i 's/precise64/dataclass/g' /etc/hostname /etc/hosts

echo "=== Provision script finished!"
echo "Change timezone: sudo dpkg-reconfigure tzdata"
echo "Change hostname: sudo pico /etc/hostname && sudo pico /etc/hosts"
echo ""
echo "If you have renamed the vm with '-n', execute 'vagrant reload' to finish the process."

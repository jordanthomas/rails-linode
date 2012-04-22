#!/bin/bash
# 
# Installs Ruby 1.9.3-p125, and Nginx with Passenger. 
#
# <UDF name="db_password" Label="MySQL root password" />
# <UDF name="deploy_password" Label="Deployment user password" />

NGINX_INSTALL_PATH="/usr/local/nginx"
NGINX_DAEMON_PATH="/usr/local/nginx/sbin/nginx"
RUBY_VERSION="ruby-1.9.3-p125"

# Update packages and install essentials
apt-get update
apt-get -y upgrade

apt-get -y install \
build-essential \
zlib1g-dev \
libssl-dev \
libreadline5-dev \
libyaml-dev \
libcurl4-openssl-dev \
libxslt1-dev \
libxml2-dev \
git-core \
python-software-properties

add-apt-repository ppa:chris-lea/node.js
apt-get update
apt-get -y install nodejs

# Set up MySQL
echo "mysql-server-5.1 mysql-server/root_password password $DB_PASSWORD" | debconf-set-selections
echo "mysql-server-5.1 mysql-server/root_password_again password $DB_PASSWORD" | debconf-set-selections

apt-get -y install \
mysql-server \
mysql-client

sleep 5

PERCENT=40
MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo) # how much memory in MB this system has
MYMEM=$((MEM*PERCENT/100)) # how much memory we'd like to tune mysql with
MYMEMCHUNKS=$((MYMEM/4)) # how many 4MB chunks we have to play with

# mysql config options we want to set to the percentages in the second list, respectively
OPTLIST=(key_buffer sort_buffer_size read_buffer_size read_rnd_buffer_size myisam_sort_buffer_size query_cache_size)
DISTLIST=(75 1 1 1 5 15)

for opt in ${OPTLIST[@]}; do
    sed -i -e "/\[mysqld\]/,/\[.*\]/s/^$opt/#$opt/" /etc/mysql/my.cnf
done

for i in ${!OPTLIST[*]}; do
    val=$(echo | awk "{print int((${DISTLIST[$i]} * $MYMEMCHUNKS/100))*4}")
    if [ $val -lt 4 ]
        then val=4
    fi
    config="${config}\n${OPTLIST[$i]} = ${val}M"
done
	
sed -i -e "s/\(\[mysqld\]\)/\1\n$config\n/" /etc/mysql/my.cnf

# Set up Postfix
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mailname string localhost" | debconf-set-selections
echo "postfix postfix/destinations string localhost.localdomain, localhost" | debconf-set-selections

apt-get -y install postfix

/usr/sbin/postconf -e "inet_interfaces = loopback-only"

# Change to temp directory
cd /tmp

# Set up Ruby
wget ftp://ftp.ruby-lang.org/pub/ruby/1.9/$RUBY_VERSION.tar.gz
tar xzf $RUBY_VERSION.tar.gz
rm "$RUBY_VERSION.tar.gz"
cd $RUBY_VERSION
./configure
make
make install
cd ..
rm -rf $RUBY_VERSION

# Set up mysql-ruby
apt-get -y install \
libmysql-ruby \
libmysqlclient-dev

# Set up gems
gem update --system
gem install bundler --no-ri --no-rdoc
gem install passenger --no-ri --no-rdoc

# Set up nginx+passenger
passenger-install-nginx-module --auto --auto-download --prefix="$NGINX_INSTALL_PATH"

# Set up nginx init script
wget https://raw.github.com/jordanthomas/nginx-init-ubuntu/master/nginx
mv nginx /etc/init.d/
chmod +x /etc/init.d/nginx
/usr/sbin/update-rc.d -f nginx defaults

# Add deploy user
echo "deploy:$DEPLOY_PASSWORD:1000:1000::/home/deploy:/bin/bash" | newusers
cp -a /etc/skel/.[a-z]* /home/deploy/
chown -R deploy /home/deploy
echo "deploy    ALL=(ALL) ALL" >> /etc/sudoers

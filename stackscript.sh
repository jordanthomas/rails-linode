#!/bin/bash
# 
# Installs Ruby 1.9.3-p125, and Nginx with Passenger. 
#
# <UDF name="db_password" Label="MySQL root password" />
# <UDF name="deploy_password" Label="Deployment user password" />

NGINX_INSTALL_PATH="/usr/local/nginx"
NGINX_DAEMON_PATH="/usr/local/nginx/sbin/nginx"
RUBY_VERSION="ruby-1.9.3-p125"

# http://www.linode.com/stackscripts/view/?StackScriptID=1
source <ssinclude StackScriptID=1>  # Common bash functions

function log {
  echo "$1 `date '+%D %T'`" >> /root/log.txt
}

cd /tmp

# Update packages and install essentials
log "Updating system... "
system_update
log "System updated!"

log "Installing essentials... "
apt-get -y install build-essential zlib1g-dev libssl-dev libreadline5-dev openssh-server libyaml-dev libcurl4-openssl-dev libxslt-dev libxml2-dev
goodstuff
log "Essentials installed!"

# Set up MySQL
log "Installing MySQL... "
mysql_install "$DB_PASSWORD" && mysql_tune 40
log "MySQL installed!"

# Set up Postfix
log "Installing Postfix... "
postfix_install_loopback_only
log "Postfix installed!"

# Installing Ruby
log "Installing $RUBY_VERSION... "

log "Downloading ftp://ftp.ruby-lang.org/pub/ruby/1.9/$RUBY_VERSION.tar.gz):"
log `wget ftp://ftp.ruby-lang.org/pub/ruby/1.9/$RUBY_VERSION.tar.gz`

log `tar xzf $RUBY_VERSION.tar.gz`
rm "$RUBY_VERSION.tar.gz"
cd $RUBY_VERSION

log "Ruby configuration output:"
log `./configure` 

log ""
log "Ruby make output:"
log `make`

log ""
log "Ruby make install output:"
log `make install` 

cd ..
rm -rf $RUBY_VERSION

log "Ruby installed!"

# Set up Nginx and Passenger
log "Installing Nginx and Passenger... " 
gem install passenger
passenger-install-nginx-module --auto --auto-download --prefix="$NGINX_INSTALL_PATH"
log "Passenger and Nginx installed!"

# Configure nginx to start automatically
cat >> /etc/init.d/nginx << EOF
#! /bin/sh

### BEGIN INIT INFO
# Provides:          nginx
# Required-Start:    $all
# Required-Stop:     $all
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: starts the nginx web server
# Description:       starts nginx using start-stop-daemon
### END INIT INFO

PATH="/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin"
DAEMON="$NGINX_DAEMON_PATH"
N="/etc/init.d/nginx"

test -x \$DAEMON || exit 0

set -e

case "\$1" in
	start)
		echo -n "Starting Nginx... "
		start-stop-daemon --start --quiet --pidfile /usr/local/nginx/logs/nginx.pid --exec \$DAEMON -- \$DAEMON_OPTS
		echo "Done!"
		;;
	stop)
		echo -n "Stopping Nginx... "
		start-stop-daemon --stop --quiet --pidfile /usr/local/nginx/logs/nginx.pid --exec \$DAEMON
		echo "Done!"
		;;
	restart|force-reload)
		echo -n "Restarting Nginx... "
		start-stop-daemon --stop --quiet --pidfile /usr/local/nginx/logs/nginx.pid --exec \$DAEMON
		sleep 1
		start-stop-daemon --start --quiet --pidfile /usr/local/nginx/logs/nginx.pid --exec \$DAEMON -- \$DAEMON_OPTS
		echo "Done!"
		;;
	reload)
		echo -n "Reloading Nginx configuration... "
		start-stop-daemon --stop --signal HUP --quiet --pidfile /usr/local/nginx/logs/nginx.pid --exec \$DAEMON
		echo "Done!"
		;;
	*)
	echo "Usage: \$N {start|stop|restart|reload|force-reload}" >&2
	exit 1
	;;
esac

exit 0

EOF

chmod +x /etc/init.d/nginx
/usr/sbin/update-rc.d -f nginx defaults
log "Nginx configured to start automatically."

# Install git
apt-get -y install git-core

# Update rubygems
gem update --system

# Install rails
gem install rails --no-ri --no-rdoc

# Install sqlite gem
apt-get -y install sqlite3 libsqlite3-dev
gem install sqlite3-ruby --no-ri --no-rdoc

# Install mysql gem
apt-get -y install libmysql-ruby libmysqlclient-dev
gem install mysql2 --no-ri --no-rdoc

# Add deploy user
echo "deploy:$DEPLOY_PASSWORD:1000:1000::/home/deploy:/bin/bash" | newusers
cp -a /etc/skel/.[a-z]* /home/deploy/
chown -R deploy /home/deploy
echo "deploy    ALL=(ALL) ALL" >> /etc/sudoers

# Spit & polish
restartServices
log "StackScript Finished!"

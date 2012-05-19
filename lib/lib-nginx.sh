#!/bin/bash

#nginx settings
NGINX_VER="1.0.20"
NGINX_PREFIX="/opt/nginx"
NGINX_SBIN_PATH="$NGINX_PREFIX/sbin/nginx"
NGINX_CONF_PATH="$NGINX_PREFIX/conf"
NGINX_PID_PATH="/var/run/nginx.pid"
NGINX_ERROR_LOG_PATH="/var/log/nginx/error.log"
NGINX_HTTP_LOG_PATH="/var/log/nginx"
NGINX_COMPILE_WITH_MODULES="--with-http_stub_status_module"

NGINX_SITES_AVAILABLE="$NGINX_CONF_PATH/sites-available"
NGINX_SITES_ENABLED="$NGINX_CONF_PATH/sites-enabled"
NGINX_TEMPLATE_DIR="/usr/local/lib/bash_stack/templates"
WEB_DIR="/var/www"

NGINX_USER_DEFAULT="www-data"
NGINX_GROUP_DEFAULT="www-data"

LOGRO_FREQ="monthly"
LOGRO_ROTA="12"

APACHE_HTTP_PORT=8080
APACHE_HTTPS_PORT=8443


NGINX_SSL_ID="nginx_ssl"


#################################
#	PHP-FPM			#
#################################


function php_fpm_install
{
	if [ ! -n "$1" ]; then
		echo "install_php_fpm requires server user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "install_php_fpm requires server group as its second argument"
		return 1;
	fi

	local PHP_FPM_USER="$1"
	local PHP_FPM_GROUP="$2"


	#installing only the basics.
	mkdir -p /var/www  #required to install php5-fpm -- it's a bug in Ubuntu
	aptitude install -y php5-fpm php5-mysql php5-pgsql php5-common php5-suhosin php5-cli php5-imagick imagemagick
 
	#php5-fpm conf
	php_fpm_conf_file=`grep -R "^listen.*=.*127" /etc/php5/fpm/* | sed 's/:.*$//g' | uniq | head -n 1`


	#sockets > ports. Using the 127.0.0.1:9000 stuff needlessly introduces TCP/IP overhead.
	sed -i 's/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/'  $php_fpm_conf_file
	
	#sockets limited by net.core.somaxconn and listen.backlog to 128 by default, so increase this
	#see http://www.saltwaterc.eu/nginx-php-fpm-for-high-loaded-websites.html
	sed -i 's/^.*listen.backlog.*$/listen.backlog = 1024/g'                $php_fpm_conf_file
	echo "net.core.somaxconn=1024" >/etc/sysctl.d/10-unix-sockets.conf
	sysctl net.core.somaxconn=1024
	
	#set max requests to deal with any possible memory leaks
	sed -i 's/^.*pm.max_requests.*$/pm.max_requests = 1024/g'              $php_fpm_conf_file


	#nice strict permissions
	sed -i 's/;listen.owner = www-data/listen.owner = '"$PHP_FPM_USER"'/'  $php_fpm_conf_file
	sed -i 's/;listen.group = www-data/listen.group = '"$PHP_FPM_GROUP"'/' $php_fpm_conf_file
	sed -i 's/;listen.mode = 0666/listen.mode = 0600/'                     $php_fpm_conf_file

	
	#these settings are fairly conservative and can probably be increased without things melting
	sed -i 's/pm.max_children = 50/pm.max_children = 12/'           $php_fpm_conf_file
	sed -i 's/pm.start_servers = 20/pm.start_servers = 4/'          $php_fpm_conf_file
	sed -i 's/pm.min_spare_servers = 5/pm.min_spare_servers = 2/'   $php_fpm_conf_file
	sed -i 's/pm.max_spare_servers = 35/pm.max_spare_servers = 4/'  $php_fpm_conf_file
	sed -i 's/pm.max_requests = 0/pm.max_requests = 500/'           $php_fpm_conf_file

 
	#Engage.
	/etc/init.d/php5-fpm restart
}

function perl_fcgi_install
{
	aptitude install -y build-essential psmisc libfcgi-perl fcgiwrap
	/etc/init.d/fcgiwrap start
}



function nginx_create_site
{
	# Based on script from http://www.sebdangerfield.me.uk/2011/03/automatically-creating-new-virtual-hosts-with-nginx-bash-script/

	
	SED=`which sed`
	CURRENT_DIR=`dirname $0`

	if [ -z $1 ]; then
		echo "No domain name given"
		exit 1
	fi
	DOMAIN=$1

	# check the domain is roughly valid!
	PATTERN="^([[:alnum:]]([[:alnum:]\-]{0,61}[[:alnum:]])?\.)+[[:alpha:]]{2,6}$"
	if [[ "$DOMAIN" =~ $PATTERN ]]; then
		DOMAIN=`echo $DOMAIN | tr '[A-Z]' '[a-z]'`
		echo "Creating hosting for:" $DOMAIN
	else
		echo "invalid domain name $DOMAIN"
		exit 1 
	fi

	#Replace dots with underscores
	SITE_DIR=`echo $DOMAIN | $SED 's/\./_/g'`

	# verify required site site conf directories exist
	sudo mkdir -p $NGINX_SITES_AVAILABLE
	sudo mkdir -p $NGINX_SITES_ENABLED

	# Now we need to copy the virtual host template
	CONFIG=$NGINX_SITES_AVAILABLE/$DOMAIN.conf
	sudo cp $NGINX_TEMPLATE_DIR/virtual_host.template $CONFIG
	sudo $SED -i "s/DOMAIN/$DOMAIN/g" $CONFIG
	sudo $SED -i "s!ROOT!$WEB_DIR/$SITE_DIR!g" $CONFIG

	# set up web root
	sudo mkdir $WEB_DIR/$SITE_DIR
	sudo chown $NGINX_USER_DEFAULT:$NGINX_GROUP_DEFAULT -R $WEB_DIR/$SITE_DIR
	sudo chmod 600 $CONFIG

	# create symlink to enable site
	sudo ln -s $CONFIG $NGINX_SITES_ENABLED/$DOMAIN.conf

	# reload Nginx to pull in new config
	sudo /etc/init.d/nginx reload

	# put the template index.html file into the new domains web dir
	sudo cp $NGINX_TEMPLATE_DIR/index.html.template $WEB_DIR/$SITE_DIR/index.html
	sudo $SED -i "s/SITE/$DOMAIN/g" $WEB_DIR/$SITE_DIR/index.html
	sudo chown $NGINX_USER_DEFAULT:$NGINX_GROUP_DEFAULT $WEB_DIR/$SITE_DIR/index.html

	echo "Site Created for $DOMAIN"
}


function nginx_install 
{
	if [ ! -n "$1" ]; then
		echo "nginx_install requires server user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "nginx_install requires server group as its second argument"
		return 1;
	fi

	local NGINX_USER="$1"
	local NGINX_GROUP="$2"
	local NGINX_USE_PHP="$3"
	local NGINX_USE_PERL="$4"
	local NGINX_SERVER_STRING="$5"

	if [ -z "$NGINX_USE_PHP" ] ; then
		NGINX_USE_PHP=1
	fi

	if [ -z "$NGINX_SERVER_STRING" ] ; then
		NGINX_SERVER_STRING=$(randomString 25)
	fi

	if [ "$NGINX_USE_PHP" = 1 ] ; then
		php_fpm_install "$NGINX_USER" "$NGINX_GROUP"
	fi

	if [ "$NGINX_USE_PERL" = 1 ] ; then
		perl_fcgi_install
	fi



	local curdir=$(pwd)

	#theres a couple dependencies.
	aptitude install -y libpcre3-dev libcurl4-openssl-dev libssl-dev


	#not nginx specific deps
	aptitude install -y wget build-essential

	#need dpkg-dev for no headaches when apt-get source nginx
	aptitude install -y dpkg-dev

	#directory to play in
	mkdir /tmp/nginx
	cd /tmp/nginx

	#grab and extract
	wget "http://nginx.org/download/nginx-$NGINX_VER.tar.gz"
	tar -xzvf "nginx-$NGINX_VER.tar.gz"

	#Camouflage NGINX Server Version String....
	perl -pi -e "s/\"Server:.*CRLF/\"Server: $NGINX_SERVER_STRING\" CRLF/g"                "nginx-$NGINX_VER/src/http/ngx_http_header_filter_module.c"
	perl -pi -e "s/\"Server:[\t ]+nginx\"/\"Server: $NGINX_SERVER_STRING\"/g"              "nginx-$NGINX_VER/src/http/ngx_http_header_filter_module.c"
	
	#Don't inform user of what server is running when responding with an error code
	perl -pi -e "s/\<hr\>\<center\>.*<\/center\>/<hr><center>Server Response<\/center>/g"  "nginx-$NGINX_VER/src/http/ngx_http_special_response.c"


	#maek eet
	cd "nginx-$NGINX_VER"

	nginx_conf_file="$NGINX_CONF_PATH/nginx.conf"
	nginx_http_log_file="$NGINX_HTTP_LOG_PATH/access.log"


	./configure --prefix="$NGINX_PREFIX" --sbin-path="$NGINX_SBIN_PATH" --conf-path="$nginx_conf_file" --pid-path="$NGINX_PID_PATH" \
	--error-log-path="$NGINX_ERROR_LOG_PATH" --http-log-path="$nginx_http_log_file" --user="$NGINX_USER" --group="$NGINX_GROUP" \
	--with-http_ssl_module --with-debug "$NGINX_COMPILE_WITH_MODULES"


	make
	make install

	#grab source for ready-made scripts
	apt-get source nginx
	
	#alter init to match sbin path specified in configure. add to init.d
	sed -i "s@DAEMON=/usr/sbin/nginx@DAEMON=$NGINX_SBIN_PATH@" nginx-*/debian/*init.d
	cp nginx-*/debian/*init.d /etc/init.d/nginx
	chmod 744 /etc/init.d/nginx
	update-rc.d nginx defaults

	#use provided logrotate file. adjust as you please
	sed -i "s/daily/$LOGRO_FREQ/" nginx-*/debian/*logrotate
	sed -i "s/52/$LOGRO_ROTA/" nginx-*/debian/*logrotate
	cp nginx*/debian/*logrotate /etc/logrotate.d/nginx



	#setup default nginx config files
	echo "fastcgi_param  SCRIPT_FILENAME   \$document_root\$fastcgi_script_name;" >> "$NGINX_CONF_PATH/fastcgi_params";
	cat <<EOF >$NGINX_CONF_PATH/nginx.conf

worker_processes 4;

events
{
	worker_connections 1024;
}
http
{
	include             mime.types;
	default_type        application/octet-stream;

	server_names_hash_max_size       4096;
	server_names_hash_bucket_size    4096;		

	#proxy settings (only relevant when nginx used as a proxy)
	proxy_set_header Host \$host;
	proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
	proxy_set_header X-Real-IP \$remote_addr;


	keepalive_timeout   65;
	sendfile            on;

	#gzip               on;
	#tcp_nopush         on;
	
	include $NGINX_CONF_PATH/sites-enabled/*;
}
EOF


	mkdir -p "$NGINX_CONF_PATH/sites-enabled"
	mkdir -p "$NGINX_CONF_PATH/sites-available"

	#create default site & start nginx
	#nginx_create_site "default" "localhost" "0" "" "$NGINX_USE_PHP" "$NGINX_USE_PERL"
	#nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "" "$NGINX_USE_PHP" "$NGINX_USE_PERL"

	#nginx_ensite      "default"
	#nginx_ensite      "$NGINX_SSL_ID"
	

	#delete build directory
	chown -R www-data:www-data /srv/www


	#return to original directory
	cd "$curdir"
}
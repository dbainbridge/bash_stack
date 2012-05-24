#!/bin/bash

#nginx settings
NGINX_VER="1.2.0"
NGINX_PREFIX="/opt/nginx"
NGINX_SBIN_PATH="$NGINX_PREFIX/sbin/nginx"
NGINX_CONF_PATH="$NGINX_PREFIX/conf"
NGINX_PID_PATH="/var/run/nginx.pid"
NGINX_ERROR_LOG_PATH="/var/log/nginx/error.log"
NGINX_HTTP_LOG_PATH="/var/log/nginx"
NGINX_COMPILE_WITH_MODULES="--with-http_stub_status_module"

NGINX_SITES_AVAILABLE="$NGINX_CONF_PATH/sites-available"
NGINX_SITES_ENABLED="$NGINX_CONF_PATH/sites-enabled"

NGINX_USER_DEFAULT="www-data"
NGINX_GROUP_DEFAULT="www-data"

DEFAULT_TEMPLATE_DIR="/usr/local/lib/bash_stack/templates"
USER_TEMPLATE_DIR="/home/$SUDO_USER/nginxmksite_templates"

LOGRO_FREQ="monthly"
LOGRO_ROTA="12"
LOGROTATE_CONF_DIR="/etc/logrotate.d"
LOGROTATE_SITES_DIR="$LOGROTATE_CONF_DIR/sites.d"

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


function nginx_ensite
{
	local server_id="$1"
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id" 
	ln -s "$NGINX_CONF_PATH/sites-available/$server_id" "$NGINX_CONF_PATH/sites-enabled/$server_id" 
	/etc/init.d/nginx restart
}

function nginx_dissite
{
	local server_id="$1"
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id"
	/etc/init.d/nginx restart
}


# mk_* functions from from apache a2mksite.sh script with mods for nginx
function mk_site {
  [[ ! -d $SITE_DIR ]] || rm -R "$SITE_DIR"
  echo "Creating $PUBLIC_DIR..."
  mkdir -p "$PUBLIC_DIR"
  echo "done!"
  if [[ -d $PUBLIC_TEMPLATE ]]
    then
    echo "Copying public $PUBLIC_TEMPLATE to $SITE_DIR..."
    cp -Rp "$PUBLIC_TEMPLATE" "$SITE_DIR"
    echo "done!"
  fi

  #simple substition in template files
  for fileTemplate in "$PUBLIC_DIR/"*.template
	do
	  $SED -i "s/SITE/$DOMAIN/g" "$fileTemplate"
	  mv "$fileTemplate" "${fileTemplate/.template}"
	done
  
  sudo chown -R $NGINX_USER_DEFAULT:$NGINX_GROUP_DEFAULT "$SITE_DIR"
}

function mk_logs {
  if [[ ! -d $LOG_DIR ]]
    then
    echo "Creating log dir: $LOG_DIR..."
    mkdir "$LOG_DIR"
    echo "done!"
  fi
  
  touch "$LOG_DIR/access.log"
  touch "$LOG_DIR/error.log"

  echo "Chowning log dir to root..."
  chown -R 0:$SUDO_GID "$LOG_DIR"
  echo "done!"

  echo "Chmoding log dir to 1750..."
  chmod -R 750 "$LOG_DIR"
  chmod 1750 "$LOG_DIR"
  echo "done!"
}

function mk_nginx_site_conf {

  echo "Creating nginx config file: $NGINX_SITE_CONF..."
  sed -e "s:LOG_DIR:$LOG_DIR:g"\
      -e "s:ROOT:$PUBLIC_DIR:g"\
      -e "s:DOMAIN:$DOMAIN:g"\
      "$SERVER_BLOCK_TEMPLATE" > "$NGINX_SITE_CONF"
  echo "done!"

  echo "Chowning nginx config file to root..."
  chown 0:$SUDO_GID "$NGINX_SITE_CONF"
  echo "done!"

  echo "Chmoding nginx config file to 740..."
  chmod 740 "$NGINX_SITE_CONF"
  echo "done!"
}


function mk_logrotate_conf {
  echo "Creating logrotate config file: $LOGROTATE_CONF..."
  sed -e "s:LOG_DIR:$LOG_DIR:g" "$LOGROTATE_TEMPLATE" > "$LOGROTATE_CONF"
  echo "done!"

  echo "Chowning logrotate config file to root..."
  chown 0:$SUDO_GID "$LOGROTATE_CONF"
  echo "done!"

  echo "Chmoding logrotate file to 740..."
  chmod 740 "$LOGROTATE_CONF"
  echo "done!"
}

function nginx_create_site
{
	# Based on script from http://www.sebdangerfield.me.uk/2011/03/automatically-creating-new-virtual-hosts-with-nginx-bash-script/
    # Based on https://github.com/postpostmodern/a2mksite
	
	SED=`which sed`
	CURRENT_DIR=`dirname $0`

	if [ -z $1 ]; then
		echo "No domain name given"
		exit 1
	fi

	if [[ -z "$SUDO_USER" ]]
      then
        echo "Use sudo"
        exit
    fi

	DOMAIN=$1
    CHOICES="Overwrite Skip"

	# check the domain is roughly valid!
	PATTERN="^([[:alnum:]]([[:alnum:]\-]{0,61}[[:alnum:]])?\.)+[[:alpha:]]{2,6}$"
	if [[ "$DOMAIN" =~ $PATTERN ]]; then
		DOMAIN=`echo $DOMAIN | tr '[A-Z]' '[a-z]'`
		echo "########  Creating hosting for: $DOMAIN  ########"
	else
		echo "invalid domain name $DOMAIN"
		exit 1 
	fi

	#Replace dots with underscores
	SITE_NAME=`echo $DOMAIN | $SED 's/\./_/g'`
    SITES_DIR="/var/www/sites"
    SITE_DIR=$SITES_DIR/$SITE_NAME

    NGINX_SITE_CONF="$NGINX_SITES_AVAILABLE/$DOMAIN"
    PUBLIC_DIR="$SITE_DIR/public"
    LOG_DIR="$SITE_DIR/log"
    LOGROTATE_CONF="$LOGROTATE_SITES_DIR/$DOMAIN.conf"

	# Determine template directories ========================

	# Choose the user's public/ template first
	# If it doesn't exist, use the default
	if [[ -d "$USER_TEMPLATE_DIR/public" ]]
	  then PUBLIC_TEMPLATE="$USER_TEMPLATE_DIR/public"
	elif [[ -d "$DEFAULT_TEMPLATE_DIR/public" ]]
	  then PUBLIC_TEMPLATE="$DEFAULT_TEMPLATE_DIR/public"
	else
	  echo "No public/ template can be found. Aborted."
	  exit
	fi

	# Choose the user's server_block.template first
	# If it doesn't exist, use the default
	if [[ -f "$USER_TEMPLATE_DIR/server_block.template" ]]
	  then SERVER_BLOCK_TEMPLATE="$USER_TEMPLATE_DIR/server_block.template"
	elif [[ -f "$DEFAULT_TEMPLATE_DIR/server_block.template" ]]
	  then SERVER_BLOCK_TEMPLATE="$DEFAULT_TEMPLATE_DIR/server_block.template"
	else
	  echo "No server_block.template can be found. Aborted."
	  exit
	fi

	# Choose the user's logrotate.conf template first
	# If it doesn't exist, use the default
	if [[ -f "$USER_TEMPLATE_DIR/logrotate.conf" ]]
	  then LOGROTATE_TEMPLATE="$USER_TEMPLATE_DIR/logrotate.conf"
	elif [[ -f "$DEFAULT_TEMPLATE_DIR/logrotate.conf" ]]
	  then LOGROTATE_TEMPLATE="$DEFAULT_TEMPLATE_DIR/logrotate.conf"
	else 
	  echo "No logrotate.conf template can be found. Aborted."
	  exit
	fi


# Create necessary directories ==========================

if [[ ! -d "$NGINX_SITES_AVAILABLE" ]]
  then 
  mkdir -p "$NGINX_SITES_AVAILABLE"
  chgrp $SUDO_GID "$NGINX_SITES_AVAILABLE"
fi
if [[ ! -d "$LOGROTATE_SITES_DIR" ]]
  then 
  mkdir -p "$LOGROTATE_SITES_DIR"
  chgrp $SUDO_GID "$LOGROTATE_SITES_DIR"
fi
if [[ ! -d "$SITES_DIR" ]]
  then 
  mkdir -p "$SITES_DIR"
  chown $SUDO_USER:$SUDO_GID "$SITES_DIR"
fi

# Create logrotate conf file for all sites ===============

if [[ ! -f "$LOGROTATE_CONF_DIR/sites" ]]
  then
  echo "include $LOGROTATE_SITES_DIR" > "$LOGROTATE_CONF_DIR/sites"
  chgrp $SUDO_GID "$LOGROTATE_CONF_DIR/sites"
fi
  

	if [[ -d "$SITE_DIR" ]] 
	  then
	  echo "$SITE_DIR already exists..."
	  select choice in $CHOICES; do
	    if [ $choice ]; then
	      case $choice in
	        Overwrite)
	          mk_site
	          break;;
	        Skip) break;;
	        esac
	    else
	      echo 'Invalid selection'
	    fi
	  done
	else
	  mk_site
	fi

	mk_logs

	if [[ -f "$NGINX_SITE_CONF" ]] 
	  then
	  echo "$NGINX_SITE_CONF already exists..."
	  select choice in $CHOICES; do
	    if [ $choice ]; then
	      case $choice in
	        Overwrite)
	          mk_nginx_site_conf
	          break;;
	        Skip) break;;
	        esac
	    else
	      echo 'Invalid selection'
	    fi
	  done
	  else
	  mk_nginx_site_conf
	fi

	if [[ -f "$LOGROTATE_CONF" ]] 
	  then
	  echo "$LOGROTATE_CONF already exists..."
	  select choice in $CHOICES; do
	    if [ $choice ]; then
	      case $choice in
	        Overwrite)
	          mk_logrotate_conf
	          break;;
	        Skip) break;;
	        esac
	    else
	      echo 'Invalid selection'
	    fi
	  done
	  else
	  mk_logrotate_conf
	fi

	# verify required site site conf directories exist
	sudo mkdir -p $NGINX_SITES_AVAILABLE
	sudo mkdir -p $NGINX_SITES_ENABLED


	# set up web root
	sudo mkdir -p $SITE_DIR
	sudo chown $NGINX_USER_DEFAULT:$NGINX_GROUP_DEFAULT -R $SITE_DIR
	sudo chmod 600 $CONFIG

	nginx_ensite $DOMAIN
	# create symlink to enable site
	#sudo ln -s $CONFIG $NGINX_SITES_ENABLED/$DOMAIN.conf

	echo "Site Created for $DOMAIN"

	# reload Nginx to pull in new config
	sudo "$NGINX_SBIN_PATH" -s reload

}


function mk_nginx_conf {

  echo "Creating main nginx config file: $NGINX_SITE_CONF..."
  sed -e "s:NGINX_CONF_PATH:$NGINX_CONF_PATH:g"\
      -e "s:ROOT:$PUBLIC_DIR:g"\
      -e "s:DOMAIN:$DOMAIN:g"\
      "$NGINX_CONF_TEMPLATE" > "$NGINX_CONF_FILE"
  echo "done!"

  echo "Chowning nginx config file to root..."
  chown 0:$SUDO_GID "$NGINX_CONF_FILE"
  echo "done!"

  echo "Chmoding nginx config file to 740..."
  chmod 740 "$NGINX_CONF_FILE"
  echo "done!"
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


	# Choose the user's basic_nginx.conf template first
	# If it doesn't exist, use the default
	if [[ -f "$USER_TEMPLATE_DIR/basic_nginx.conf" ]]
	  then NGINX_CONF_TEMPLATE="$USER_TEMPLATE_DIR/basic_nginx.conf"
	elif [[ -f "$DEFAULT_TEMPLATE_DIR/basic_nginx.conf" ]]
	  then NGINX_CONF_TEMPLATE="$DEFAULT_TEMPLATE_DIR/basic_nginx.conf"
	else 
	  echo "No basic_nginx.conf template can be found. Aborted."
	  exit
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

	NGINX_CONF_FILE="$NGINX_CONF_PATH/nginx.conf"
	nginx_http_log_file="$NGINX_HTTP_LOG_PATH/access.log"


	./configure --prefix="$NGINX_PREFIX" --sbin-path="$NGINX_SBIN_PATH" --conf-path="$NGINX_CONF_FILE" --pid-path="$NGINX_PID_PATH" \
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

	#setup main nginx config file
	mk_nginx_conf


	mkdir -p "$NGINX_CONF_PATH/sites-enabled"
	mkdir -p "$NGINX_CONF_PATH/sites-available"


	#create default site & start nginx
	#nginx_create_site "default" "localhost" "0" "" "$NGINX_USE_PHP" "$NGINX_USE_PERL"
	#nginx_create_site "$NGINX_SSL_ID" "localhost" "1" "" "$NGINX_USE_PHP" "$NGINX_USE_PERL"

	#nginx_ensite      "default"
	#nginx_ensite      "$NGINX_SSL_ID"
	

	#delete build directory
	rm -rf /tmp/nginx
	#chown -R www-data:www-data /srv/www


	#return to original directory
	cd "$curdir"
}
#!/bin/bash


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


######################
# Ruby / Rails       #
######################

function ruby_install
{
	local curdir=$(pwd)
	
	ruby_ee_source_url=$(echo $(wget -O-  http://www.rubyenterpriseedition.com/download.html 2>/dev/null ) | egrep -o 'href="[^\"]*\.tar\.gz' | sed 's/^href="//g')
	mkdir /tmp/ruby
	cd /tmp/ruby

	aptitude install -y build-essential zlib1g-dev libssl-dev
	aptitude install -y libreadline5-dev >/dev/null 2>&1
	aptitude install -y libreadline6-dev >/dev/null 2>&1
	aptitude install -y libreadline-dev  >/dev/null 2>&1


	wget "$ruby_ee_source_url"
	tar xvzf *.tar.gz
	rm -rf *.tar.gz

	
	cd ruby*
	if [ -e "source/ext/openssl/ossl_ssl.c" ] ; then
		sed -i 's/OSSL_SSL_METHOD_ENTRY.SSLv2[\)_].*$/ /g' "source/ext/openssl/ossl_ssl.c"
	fi
	
	./installer --auto "$RUBY_PREFIX"
	for ex in erb gem irb rackup rails rake rdoc ri ruby bundle ; do
		ln -s "$RUBY_PREFIX/bin/$ex" "/usr/bin/$ex"
	done

        # Install rails
        gem install rails --no-ri --no-rdoc


	cd "$curdir"
	rm -rf /tmp/ruby
}

#################################
#	nginx			#
#################################

function nginx_create_site_old
{
	local server_id="$1"
	local server_name_list="$2"
	local is_ssl="$3"
	local rails_paths="$4"
	local enable_php="$5"
	local enable_perl="$6"

	port="80"
	ssl_cert=""
	ssl_ckey=""
	ssl=""
	if [ "$is_ssl" = "1" ] ; then
		port="443"
		ssl="ssl                  on;"
		ssl_cert="ssl_certificate      $NGINX_CONF_PATH/ssl/nginx.pem;"
		ssl_ckey="ssl_certificate_key  $NGINX_CONF_PATH/ssl/nginx.key;"
		if [ ! -e "$NGINX_CONF_PATH/ssl/nginx.pem" ] || [ ! -e "$NGINX_CONF_PATH/ssl/nginx.key"  ] ; then
			aptitude install -y ssl-cert
			mkdir -p "$NGINX_CONF_PATH/ssl"
			make-ssl-cert generate-default-snakeoil --force-overwrite
			cp /etc/ssl/certs/ssl-cert-snakeoil.pem    "$NGINX_CONF_PATH/ssl/nginx.pem"
			cp /etc/ssl/private/ssl-cert-snakeoil.key  "$NGINX_CONF_PATH/ssl/nginx.key"
		fi
	fi

	config_path="$NGINX_CONF_PATH/sites-available/$server_id"
	cat << EOF >"$config_path"
server
{
	listen               $port;
	server_name          $server_name_list;
	access_log           $NGINX_PREFIX/$server_id/logs/access.log;
	root                 $NGINX_PREFIX/$server_id/public_html;
	index                index.html index.htm index.php index.cgi;
	$ssl
	$ssl_cert
	$ssl_ckey

	error_page	400 406 407 409 410 411 412 413 414 415 416 417 418 422 423 424 425 426 444 449 450 490 	/error/400.html;
	error_page	401	/error/401.html;
	error_page	402	/error/402.html;
	error_page	403	/error/403.html;
	error_page	404	/error/404.html;
	error_page	405	/error/405.html;
	error_page	408	/error/408.html;
 
	error_page	500 506 507 509 510	/error/500.html;
	error_page	501	/error/501.html;
	error_page	502	/error/502.html;
	error_page	503	/error/503.html;
	error_page	504	/error/504.html;
	error_page	505	/error/505.html;

	location = /error/403.html
	{
		allow all;
	}

	#rails
EOF


	if [ -z "$rails_paths" ] ; then
		cat << EOF >>"$config_path"
	#passenger_enabled   on;
	#passenger_base_uri  rails_app; ##should be symlink to public dir of actual rails_app 
EOF
	else
		echo '	passenger_enabled   on;' >>"$config_path"
		if [ "$rails_paths" != '.' ] ; then
			for rp in $rails_paths ; do
				echo "	passenger_base_uri  $rp; " >> "$config_path"
			done
		fi	
	fi

	local php_comment=""
	local perl_comment=""
	if [ "$enable_php" == '0' ] ; then
		php_comment="#"
	fi
	if [ "$enable_perl" == '0' ] ; then
		perl_comment="#"
	fi

	cat << EOF >>"$config_path"

	${php_comment}#php
	${php_comment}location ~ \.php\$
	${php_comment}{
	${php_comment}	try_files      \$uri =404;
	${php_comment}	fastcgi_pass   unix:/var/run/php-fpm.sock ;
	${php_comment}	include        $NGINX_CONF_PATH/fastcgi_params;
	${php_comment}}

	${perl_comment}#perl
	${perl_comment}location ~ \.pl\$
	${perl_comment}{
	${perl_comment}	fastcgi_pass   unix:/var/run/fcgiwrap.socket ;
	${perl_comment}	include        $NGINX_CONF_PATH/fastcgi_params;
	${perl_comment}}

EOF

	echo "}" >> "$config_path"
	

	mkdir -p "$NGINX_PREFIX/$server_id/logs"
	cp -r "$BASH_STACK_INSTALL_DIR/default_html" "$NGINX_PREFIX/$server_id/public_html"
	cat "$BASH_STACK_INSTALL_DIR/default_html/index.html" | sed "s/SERVER_ID/$server_id/g" > "$NGINX_PREFIX/$server_id/public_html/index.html"
	chown -R www-data:www-data "$NGINX_PREFIX/$server_id"

}

function nginx_delete_site
{
	local server_id="$1"
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id"
	rm -rf "$NGINX_CONF_PATH/sites-available/$server_id"
	rm -rf "$NGINX_PREFIX/$server_id"
	/etc/init.d/nginx restart
}


function nginx_add_passenger_uri_for_vhost
{
	local VHOST_CONFIG_FILE=$1
	local URI=$2

	escaped_uri=$(escape_path "$URI" )
	

	NL=$'\\\n'
	TAB=$'\\\t'
	cat "$VHOST_CONFIG_FILE" | grep -v -P "^[\t ]*passenger_base_uri[\t ]+$escaped_search_uri;"  > "$VHOST_CONFIG_FILE.tmp" 
	enabled_line=$(grep -P "^[\t #]*passenger_enabled[\t ]+" "$VHOST_CONFIG_FILE")
	if [ -n "$enabled_line" ] ; then
		
		cat   "$VHOST_CONFIG_FILE.tmp" | sed -e "s/^.*passenger_enabled.*$/${TAB}passenger_enabled   on;${NL}${TAB}passenger_base_uri  $escaped_uri;/g"  > "$VHOST_CONFIG_FILE"
	else
		cat   "$VHOST_CONFIG_FILE.tmp" | sed -e "s/^{$/{${NL}${TAB}passenger_enabled   on;${NL}${TAB}passenger_base_uri  $escaped_uri;/g"  > "$VHOST_CONFIG_FILE"
	fi
	rm -rf "$VHOST_CONFIG_FILE.tmp" 

}

function nginx_add_include_for_vhost
{
	local VHOST_CONFIG_FILE=$1
	local INCLUDE_FILE=$2

	escaped_search_include=$(escape_path "$INCLUDE_FILE" )

	
	cat "$VHOST_CONFIG_FILE" | grep -v -P "^[\t ]*include[\t ]+$escaped_search_include;" | grep -v "^}[\t ]*$"  > "$VHOST_CONFIG_FILE.tmp" 
	printf "\tinclude $INCLUDE_FILE;\n" >>"$VHOST_CONFIG_FILE.tmp"
	echo "}" >>"$VHOST_CONFIG_FILE.tmp"
	mv "$VHOST_CONFIG_FILE.tmp" "$VHOST_CONFIG_FILE"
}

function nginx_set_rails_as_vhost_root
{
	local VHOST=$1 ; shift
	local RAILS_PATH=$1 ; shift

	local vhost_config="/etc/nginx/sites-available/$VHOST"
	local rails_public_path="$RAILS_PATH/public"
	rails_public_path=$(echo "$rails_public_path"   | sed 's/public\/public$/public/g')

	local rails_public_escaped_path=$(escape_path "$rails_public_path" )
	

	#note: invoking perl like this is like sed, but better, cuz' it handles tabs properly
	perl -pi -e 's/^[\t ]*passenger_base_uri[\t ]+.*$//g'                                  $vhost_config
	perl -pi -e 's/^.*passenger_enabled[\t ]+.*$/\tpassenger_enabled   on;/g'              $vhost_config
	perl -pi -e "s/[\t ]*root[\t ]+.*$/\troot                 $rails_public_escaped_path;/g" $vhost_config
}



function get_root_for_site_id
{
	VHOST_ID=$1
	echo $(cat "/etc/nginx/sites-available/$VHOST_ID" | grep -P "^[\t ]*root"  | awk ' { print $2 } ' | sed 's/;.*$//g')
}

function get_domain_for_site_id
{
	echo $(cat "/etc/nginx/sites-available/$1" | grep server_name | sed 's/;//g' | awk ' {print $2} ')
}




#################################################################################
# Utility function for generating SSL key & certificate signing request (.csr)  #
# Useful if you need authenticated HTTPS                                        #
# key and csr files are generated in current working directory                  #
# old key and csr files are removed                                             #
#################################################################################

function gen_ssl_key_and_request
{
	local country="$1"       # 2 letter code,                     e.g. "US"
	local state="$2"         # Full name of state/province,       e.g. "Rhode Island"
	local city="$3"          # Full city name,                    e.g. "Providence"
	local organization="$4"  # Your full organization name,       e.g. "Diane's Dildo Emporium LLC"
	local org_unit="$5"      # Organizational unit, can be blank  e.g. "Web Services"
	local site_name="$6"     # Full domain name                   e.g. "www.dianesdildos.com"
	local email="$7"         # Contact email address              e.g. "dirtydiane@dianesdildos.com"
	local valid_time="$8"    # Number of days cert will be valid  e.g. "365" (for one year)

	rm -rf "$site_name.key" "$site_name.csr"
	printf "$country\n$state\n$city\n$organization\n$org_unit\n$site_name\n$email\n\n\n\n\n\n" | openssl req -new -days "$valid_time" -nodes -newkey rsa:2048 -keyout "$site_name.key" -out "$site_name.csr"

}



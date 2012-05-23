#!/bin/bash


source "/usr/local/lib/bash_stack/lib/lib-nginx.sh"
SITES_DIR="/var/www/sites"

function munin_install {
	aptitude -y install  munin munin-node
}

function munin_clone_contrib  {
    sudo git clone git://github.com/munin-monitoring/contrib.git "/usr/local/lib/bash_stack/support/munin/contrib"
}

function munin_configure_nginx {
	if [ -z $1 ]; then
		echo "No domain/subdomain name given to for munin access.  Example: munin_configure_nginx munin.mydomain.com"
		exit 1
	fi

#Note, nginx had to be compiled --with-http_stub_status_module
 	cat <<EOT >"/opt/nginx/conf/sites-available/munin"
	server {
	  listen 127.0.0.1;
	  server_name localhost;
	  location /nginx_status {
	    stub_status on;
	    access_log off;
	    allow 127.0.0.1;
	    deny all;
	  }
	}

	server {
	 listen 80;
	 server_name $1;
	 location / {
	   root /var/www/sites/munin;
	 }
	}
EOT


 	cat <<EOT >"/etc/munin/plugin-conf.d/nginx"
	[nginx_*]
	env.url http://localhost/nginx_status
EOT

 #   sed -i 's:\[localhost\.localdomain\]:\$1]:g' /etc/munin/munin.conf


	if [[ ! -d "$SITES_DIR" ]]
	  then 
	  mkdir -p "$SITES_DIR"
	  chown $SUDO_USER:$SUDO_GID "$SITES_DIR"
	fi
	ln -s /var/cache/munin/www /var/www/sites/munin
	nginx_ensite munin

	/etc/init.d/munin-node restart
}

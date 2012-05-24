Script package that I use to simplify setup of an Ubuntu server.  My usage of this script package has only been on Ubuntu 12.04 LTS.

Until there is a friendlier way to access the script functions in this package here is example usage:

    aptitude -y install git-core
    git clone git://github.com/dbainbridge/bash_stack.git
    cd bash_stack
    source install.sh

Now to install nginx from source (installs nginx 1.2.0):
    bash_stack system_enable_universe
    bash_stack nginx_install "www-data" "www-data" "0" "0" "0"

Start nginx:
    sudo /opt/nginx/sbin/nginx

A shell script "nginxcreatesite" was installed to /usr/local/bin with the "source install.sh" statement above.  You can then create a nginx virtual host/server block with the command:

    sudo nginxcreatesite mydomain.com

The web site files will be located in /var/www/sites/mydomain_com.
Access/error logs will be generated for each server block located in /var/www/sites/mydomain_com/logs
All "public" files are located in /var/www/sites/mydomain_com/public




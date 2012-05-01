#!/bin/bash

export RUBY_PREFIX="/usr/local/ruby"

#nginx settings
export NGINX_VER="1.0.20"
export NGINX_PREFIX="/opt/nginx"
export NGINX_SBIN_PATH="$NGINX_PREFIX/sbin/nginx"
export NGINX_CONF_PATH="$NGINX_PREFIX/conf"
export NGINX_PID_PATH="/var/run/nginx.pid"
export NGINX_ERROR_LOG_PATH="/var/log/nginx/error.log"
export NGINX_HTTP_LOG_PATH="/var/log/nginx"

export LOGRO_FREQ="monthly"
export LOGRO_ROTA="12"

export APACHE_HTTP_PORT=8080
export APACHE_HTTPS_PORT=8443


export NGINX_SSL_ID="nginx_ssl"

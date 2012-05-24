#!/usr/bin/env bash


# installs latest stable release of node and npm
function node_install {
	sudo apt-get install python-software-properties
	sudo apt-add-repository -y ppa:chris-lea/node.js
	sudo apt-get update
	sudo apt-get install -y nodejs npm
}

usage()
{
cat << EOF
usage: $0 options


OPTIONS:
   -t  Node.js tag (see https://github.com/joyent/node for values, optional)
   -p  Prefix where to install node (optional)
 
EOF
}

function node_install_src {

	CURRENT_DIR=`dirname $0`

	DEFAULT_NODE_TAG="v.06.18"
	DEFAULT_PREFIX="/opt/node"
	while getopts “ht:p:” OPTION
	do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         t)
             DEFAULT_NODE_TAG=$OPTARG
             ;;
         p)
             DEFAULT_PREFIX=$OPTARG
             ;;
         "?")
             usage
             exit
             ;;
     esac
	done

	mkdir -p "$DEFAULT_PREFIX/src"
    cd "$DEFAULT_PREFIX/src"

	git clone https://github.com/joyent/node.git
	cd node
	git checkout $DEFAULT_NODE_TAG #Try checking nodejs.org for what the stable version is
	./configure --prefix=/opt/node
	make
	sudo make install

	cd $CURRENT_DIR
}
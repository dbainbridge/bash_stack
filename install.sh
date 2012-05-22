#!/bin/bash

INSTALL_LOCATION="/usr/local/lib/bash_stack"
INSTALL_LOCATION_BIN="/usr/local/bin"
#INSTALL_LOCATION="/Users/dkb/bash_stack"

if [ "$1" ] ; then
	INSTALL_LOCATION="$1"
fi

#remove trailing '/'
INSTALL_LOCATION=$(echo "$INSTALL_LOCATION" | sed 's/\/$//g')

#install lib directory if lib directory exists
if [ -d ./lib ] ; then
	echo "Installing to: $INSTALL_LOCATION"

	# remove previous installation if it exists
	rm -rf "$INSTALL_LOCATION"
	mkdir -p "$INSTALL_LOCATION/lib"
    mkdir -p "$INSTALL_LOCATION/bin"

	cp -r ./lib/* "$INSTALL_LOCATION/lib"
	cp ./bash_stack.sh "$INSTALL_LOCATION"
	cp -r ./default_html "$INSTALL_LOCATION"
	if [ -d ./default_conf ] ; then
      cp -r ./default_conf "$INSTALL_LOCATION"
    fi
    cp -r ./templates "$INSTALL_LOCATION"
    cp -r ./bin/* "$INSTALL_LOCATION_BIN"
    for shellFile in "$INSTALL_LOCATION_BIN/"*
	do
	  chmod +x "$shellFile"
	done
 
	echo '#!/bin/bash' > "$INSTALL_LOCATION/tmp.tmp.sh"
	echo "BASH_STACK_INSTALL_DIR=\"$INSTALL_LOCATION\"" >> "$INSTALL_LOCATION/tmp.tmp.sh"
	cat "$INSTALL_LOCATION/bash_stack.sh"  >> "$INSTALL_LOCATION/tmp.tmp.sh"
	mv "$INSTALL_LOCATION/tmp.tmp.sh" "$INSTALL_LOCATION/bash_stack.sh"
fi

source $INSTALL_LOCATION/bash_stack.sh
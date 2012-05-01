
export BASH_STACK_INSTALL_DIR

# source all files in this directory except this script
 for f in $BASH_STACK_INSTALL_DIR/lib/*; 
 do
 	echo $f
	source "$f"
 done

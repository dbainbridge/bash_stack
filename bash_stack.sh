
export BASH_STACK_INSTALL_DIR

# source all files in this directory
 for f in $BASH_STACK_INSTALL_DIR/lib/*.sh; 
 do
	source "$f"
 done

#!/bin/bash
#
# Install common utilities
#
# Copyright (c) 2010 Filip Wasilewski <en@ig.ma>.
#
# My ref: http://www.linode.com/?r=aadfce9845055011e00f0c6c9a5c01158c452deb

function system_install_utils {
    aptitude -y install wget less vim sudo screen htop bsd-mailx
}

function system_install_build {
    aptitude -y install build-essential gcc
}

function system_install_subversion {
    aptitude -y install subversion
}

function system_install_git {
    aptitude -y install git-core
}

function system_install_mercurial {
    aptitude -y install mercurial
}

function system_install_bazaar {
    aptitude -y install bzr
}

function system_start_etc_dir_versioning {
    # etckeeper defaults to bzr VCS
    # TODO add support for other VCS
    # see http://fnords.wordpress.com/2009/02/23/etckeeper-chronicles-1/
    system_install_bazaar
    aptitude -y install etckeeper
    etckeeper init
    bzr whoami "root"
}

function system_record_etc_dir_changes {
    if [ ! -n "$1" ];
        then MESSAGE="Committed /etc changes"
        else MESSAGE="$1"
    fi
    etckeeper commit "$MESSAGE"
}

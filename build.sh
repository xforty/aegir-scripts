#!/bin/bash

# TODO: Provide parameters
makefile=${makefile:-distro.make}
web_server=${web_server:-@server_master}
platform_env=${platform_env:-dev}

# Before we do anything check to see if there is a distro.make file
if [ ! -f $makefile ]; then
  echo "The distro.make file is missing."
  exit 1
fi

# Get the correct platform 

# We assume everything to the left of the first '-' is the platform name
default_platform=`git tag -l | tail -1 | awk -F- '{ print $1 }'`

# If there are no tags we guess the name of the repo is www.sitename.com
if [ -z $default_platform ]; then
  default_platform=`git remote -v | awk -F. '{ print $4 }'`
  if [ -z $default_platform ]; then
    default_platform=$USER
  fi
fi

# Give them a chance to change it.
read -p "Platform name? [$default_platform] " -e platform

if [ -z $platform ]; then
  platform=$default_platform
fi

# Need to truncate the platform to 17 since the limit for a platform is 50 (bleh)
platform=`echo $platform | cut -c 1-17`

tag_name=$platform-$platform_env-v`date +%Y-%m-%d-%H-%M`

# Get the client name or don't set it
eval `cat distro.make | perl -pi -e's/ = /=/' | grep client_uname | grep -v ^;`
if [ -n $client_uname ]; then
  client="--client=$client_uname"
fi

# Create a tag for produciton
if [ "x$platform_env" = "xprod" ]; then 

  # If the repo is dirty don't both creating a tag.
  git status >/dev/null
  if [ $? -eq 1 ]; then
    # Create a tag
    git tag $tag_name -m "Release tag"
    git push --tags
  else
    echo "Your git repo has local modifications"
    exit
  fi

fi


#
# Create the build
# 
build_root=`pwd`

cd /tmp

# Build the platform
http_proxy="$http_proxy" drush make --tar $@ $build_root/distro.make $tag_name
if [ $? -ne 0 ]; then
  print "Erroring out"
  exit
fi

# TODO:Lock the old platform first

# create a new platform for each server.
cd /var/aegir/platforms

# Swap - for _ since Aegir can't handle it. Wah. Wah. Wah.
platform_name=`echo $tag_name | tr - _`

sudo -H -u aegir tar zxf /tmp/${tag_name}.tar.gz
# TODO:
# Or do we setaclf
sudo chmod -R  g+w /var/aegir/platforms/${tag_name}

# TODO: Does assigning the client work?
sudo -H -u aegir drush --verbose provision-save @platform_${platform_name} --context_type=platform \
        --root=/var/aegir/platforms/${tag_name} \
        $client \
        --web_server=$web_server

sudo -H -u aegir drush --verbose  @hostmaster hosting-import "@platform_${platform_name}"

rm /tmp/${tag_name}.tar.gz

# Migrate the old one

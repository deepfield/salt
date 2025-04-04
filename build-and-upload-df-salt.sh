#!/bin/bash

# builds and uploads the saltstack debian
# for more detailed instructions, see https://deepfield.atlassian.net/wiki/spaces/SYSENG/pages/3715498045/Custom+Salt+Debian

# this script should be ran in this container https://github.com/deepfield/deploy/blob/master/docker-images/salt-package-build/Dockerfile



if [ -z "$1" ]; then
  echo "Error: Missing version parameter."
  exit 1
fi


# version string parameter, should look something like 3006.9+2.df where 3006.9 follows saltstack versioning, and +2.df is a number we should increment each time we want to make a new patch
VERSION=$1
ORIGINAL_SALT_VERSION=$(echo "$VERSION" | cut -d'+' -f1)

relenv fetch

# first setup a venv and install our python dependencies
relenv create --python=3.10.15 /saltenv
/saltenv/bin/pip3 install pip-tools
/saltenv/bin/pip-compile --no-emit-index-url --output-file=requirements/static/pkg/py3.10/linux.txt requirements/base.txt requirements/deepfield.txt requirements/static/pkg/linux.in requirements/zeromq.txt
/saltenv/bin/pip3 install -r requirements/static/ci/py3.10/tools.txt

# set the version we're about to build
/saltenv/bin/tools changelog update-deb ${VERSION}

# ensure shared libraries from our venv are accessible
echo "$(pwd)/relenv/lib" > /etc/ld.so.conf.d/salt.conf
ldconfig

# build the debian. This is using the command dpkg-buildpackage which uses the rules file at pkg/debian/rules (this repo)
DEB_BUILD_MAINT_OPTIONS=optimize=-lto /saltenv/bin/tools pkg build deb --relenv-version 0.18.0 --python-version 3.10.15 --arch x86_64

mkdir debs
cp ../*.deb debs
aws s3 cp debs s3://dependencies.deepfield.net/salt/$ORIGINAL_SALT_VERSION/debian/nodist/ --recursive --exclude "*" --include "*.deb"
#!/bin/bash

# builds and uploads the saltstack debian
# for more detailed instructions, see https://deepfield.atlassian.net/wiki/spaces/SYSENG/pages/3715498045/Custom+Salt+Debian

# this script should be ran in this container https://github.com/deepfield/deploy/blob/master/docker-images/salt-package-build/Dockerfile



if [ -z "$1" ]; then
  echo "Error: Missing version parameter."
  exit 1
fi

# fail loudly: without this the build could fail while the final aws s3 cp (on an empty
# dir) exits 0, making the Jenkins job report SUCCESS with no package produced.
set -euo pipefail


# version string parameter, should look something like 3006.9+2.df where 3006.9 follows saltstack versioning, and +2.df is a number we should increment each time we want to make a new patch
VERSION=$1
ORIGINAL_SALT_VERSION=$(echo "$VERSION" | cut -d'+' -f1)

# clean generated artifacts: dpkg-source (3.0 native) tars the whole tree, so stale
# doc/_build etc. from a prior build breaks it ("tar: ... file changed as we read it").
rm -rf build debs relenv .tools-venvs doc/_build

# relenv 0.22.4 (per cicd/shared-gh-workflows-context.yml) provides the compiler toolchain
# via the ppbt package that pkg/debian/rules installs; 0.19.4 does not. Pin the fetch python.
pip3 install --upgrade "relenv==0.22.4"; relenv --version
relenv fetch --python=3.10.19

# first setup a venv and install our python dependencies
relenv create --python=3.10.19 /saltenv
# typing_extensions: current pip-tools imports it without declaring it as a dependency
/saltenv/bin/pip3 install pip-tools typing_extensions
/saltenv/bin/pip-compile --no-emit-index-url --output-file=requirements/static/pkg/py3.10/linux.txt requirements/base.txt requirements/deepfield.txt requirements/static/pkg/linux.in requirements/zeromq.txt
/saltenv/bin/pip3 install -r requirements/static/ci/py3.10/tools.txt

# Write version to file so salt reports correctly
echo $VERSION > salt/_version.txt

# set the version we're about to build
/saltenv/bin/tools changelog update-deb ${VERSION}

# ensure shared libraries are accessible. Use zzz-relenv.conf so it sorts AFTER the system
# multiarch conf: salt.conf sorted before it and shadowed the system libstdc++ with relenv's
# older one (missing GLIBCXX_3.4.30), breaking rustc when cryptography compiles.
echo "$(pwd)/relenv/lib" > /etc/ld.so.conf.d/zzz-relenv.conf
ldconfig

# build the debian. This is using the command dpkg-buildpackage which uses the rules file at pkg/debian/rules (this repo)
DEB_BUILD_MAINT_OPTIONS=optimize=-lto /saltenv/bin/tools pkg build deb --relenv-version 0.22.4 --python-version 3.10.19 --arch x86_64

mkdir -p debs
cp ../*.deb debs
aws s3 cp debs s3://dependencies.deepfield.net/salt/$ORIGINAL_SALT_VERSION/debian/nodist/ --recursive --exclude "*" --include "*.deb"

#!/bin/bash
##
## Ansible: Setup user's local Ansible environment
## Copyright (c) 2017-2021 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
umask 0022
set -o pipefail || exit $?	## bash 3.0+

pdie() {
  echo "$0: ERROR: ${1-}" 1>&2
  exit "${2-1}"
}

v() {
  echo "$({ tput bold; tput smul; } 2>/dev/null)${0##*/}: $*$(tput sgr0 2>/dev/null)"
}

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ANSIBLEDIR> [MODULE[=VERSION] ...]"
  echo
  echo "Example to install the latest version:"
  echo "  \$ $0 ~/ansible"
  echo "  ..."
  echo "  \$ source ~/ansible/bin/activate"
  echo "  \$ type ansible"
  echo "  ansible is /home/yourname/ansible/bin/ansible"
  echo "  \$ ansible localhost -m ping"
  echo "  ..."
  echo
  echo "Example to install a specific version:"
  echo "  \$ ansible_version=2.8.5.0 $0 ~/ansible"
  echo "  ..."
  exit 1
fi

v "Started."

ansible_root="$1"; shift
if [[ $ansible_root != /* ]]; then
  ansible_root="$PWD/$ansible_root"
fi

if [[ -z ${python-} ]]; then
  for python_try in /usr/libexec/platform-python python3 python; do
    if type "$python_try" >/dev/null 2>&1; then
      python="$python_try"
      break
    fi
  done
fi
if [[ -z ${python-} ]]; then
  pdie "Python not found"
fi

python_ver=$(
"$python" <<'EOF'
from __future__ import print_function
import sys
print('.'.join((str(x) for x in sys.version_info)))
EOF
)
python_ver_int=$(
"$python" <<'EOF'
from __future__ import print_function
import sys
print('%d%02d%02d' % sys.version_info[:3])
EOF
)

python_modules_pre=()
if ! "$python" -m wheel --help >/dev/null 2>&1; then
  python_modules_pre+=(
    wheel${wheel_version:+==$wheel_version}
  )
fi

python_modules=(
  ansible${ansible_version:+==$ansible_version}
  pyyaml${pyyaml_version:+==$pyyaml_version}
  jinja2${jinja2_version:+==$jinja2_version}
  cryptography${cryptography_version:+==$cryptography_version}${cryptography_version:-<3.4}
  pycrypto${pycrypto_version:+==$pycrypto_version}
  paramiko${paramiko_version:+==$paramiko_version}
  httplib2${httplib2_version:+==$httplib2_version}
  six${six_version:+==$six_version}
  netaddr${netaddr_version:+==$netaddr_version}
  jmespath${jmespath_version:+==$jmespath_version}
  xmltodict${xmltodict_version:+==$xmltodict_version}
  pywinrm${pywinrm_version:+==$pywinrm_version}
  "$@"
)

get_pip_url="${get_pip_uri:-https://bootstrap.pypa.io/get-pip.py}"

sshpass_src_base_url="https://sourceforge.net/projects/sshpass/files/sshpass"
sshpass_version="1.06"

## ----------------------------------------------------------------------

eval "$(sed 's/^\([A-Z]\)/OS_\1/' /etc/os-release)" || exit $?

## ----------------------------------------------------------------------

echo "Ansible directory: $ansible_root"
echo "Python: $python"
echo "Python version: $python_ver"
echo "Python modules:"
for module in "${python_modules[@]}"; do
  echo "  $module"
done
echo "get-pip.py: $get_pip_url"

## Check if required component to build modules exist
## ======================================================================

v "Checking C compiler to build binary modules ..."
type gcc || type cc || exit $?

v "Checking required packages to build binary modules ..."
case "$OS_ID" in
debian|ubuntu)
  buildrequires=(gcc libssl-dev libffi-dev libgmp-dev)
  if [[ $python_ver_int -ge 30000 ]];then
    buildrequires+=(python3-dev)
  else
    buildrequires+=(python-dev)
  fi
  dpkg --list --no-pager "${buildrequires[@]}" || true
  dpkg --status "${buildrequires[@]}" >/dev/null || exit $?
  ;;
redhat|centos|fedora)
  buildrequires=(gcc openssl-devel libffi-devel gmp-devel)
  if [[ ${python##*/} == platform-python && $OS_VERSION_ID -ge 8 ]]; then
    buildrequires+=(platform-python-devel)
  elif [[ $python_ver_int -ge 30000 ]];then
    buildrequires+=(python3-devel)
  else
    buildrequires+=(python-devel)
  fi
  rpm -q --qf '%{name}-%{version}-%{release}\n' "${buildrequires[@]}" \
  |sed -n -e '/ /{s/^/ERROR: /;H}' -e '/ /!p' -e '${x;s/^\n//;p}' \
  || exit $? \
  ;
  ;;
esac

## ======================================================================

export PATH="$ansible_root/bin:$PATH"
export PYTHONUSERBASE="$ansible_root"
export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
export PIP_PROGRESS_BAR=off
export XDG_CACHE_HOME="$ansible_root/var/cache/xdg"

mkdir -p "$ansible_root/bin" || exit $?
cd "$ansible_root/bin" || exit $?

## Create activate script
## ======================================================================

cat <<'EOF' >>activate || exit $?
if [ -n "${ZSH_VERSION-}" ]; then
  ansible_root=$(cd "${0%/*}/.." && pwd) || return $?
elif [ -n "${BASH_VERSION-}" ]; then
  ansible_root=$(cd "${BASH_SOURCE[0]%/*}"/.. && pwd) || return $?
elif [ -n "$KSH_VERSION" ] && [ -n "${KSH_VERSION##*MIRBSD KSH *}" ]; then
  ## AT&T ksh
  ansible_root=$(cd "${.sh.file%/*}/.." && pwd) || return $?
else
  ansible_root="$PWD"
fi

python_sitelib=$(echo "$ansible_root"/lib/python*/*)

export PATH="$ansible_root/bin:$PATH"
export PYTHONPATH="$python_sitelib"
EOF

## Backward compatibility
ln -sf activate env-setup

## Install sshpass
## ======================================================================

if [[ -x ./sshpass ]]; then
  : OK
elif type sshpass >/dev/null 2>&1; then
  v "Copying sshpass if available ..."
  sshpass_is=$(LC_ALL=C type sshpass) || exit $?
  cp -p -- "${sshpass_is#sshpass is }" ./ || exit $?
else
  case "$OS_ID" in
  debian|ubuntu)
    v "Downloading sshpass binary in *.deb package ..."
    rm -f sshpass_[0-9]*.deb || exit $?
    apt download sshpass || exit $?
    ar p sshpass_[0-9]*.deb data.tar.xz |tar -xf - --xz ./usr/bin/sshpass || exit $?
    mv ./usr/bin/sshpass ./ || exit $?
    rmdir ./usr/bin ./usr
    ;;
  redhat|centos|fedora)
    if [[ $OS_VERSION_ID -le 7 ]] || [[ $OS_ID == fedora ]]; then
      v "Downloading sshpass binary in *.rpm package ..."
      rm -f sshpass-[0-9]*.rpm || exit $?
      yumdownloader --disablerepo=\* --enablerepo=extras sshpass || exit $?
      rpm2cpio sshpass-[0-9]*.rpm |cpio -id ./usr/bin/sshpass || exit $?
      mv ./usr/bin/sshpass ./ || exit $?
      rmdir ./usr/bin ./usr
      rm -f sshpass-[0-9]*.rpm || exit $?
    else
      v "Building sshpass binary from source archive ..."
      rm -rf sshpass-[0-9]* || exit $?
      curl \
	--silent \
	--show-error \
	--location \
	--remote-name \
	"$sshpass_src_base_url/$sshpass_version/sshpass-$sshpass_version.tar.gz" \
      || exit $?
      tar xf "sshpass-$sshpass_version.tar.gz" || exit $?
      pushd "sshpass-$sshpass_version" || exit $?
      ./configure || exit $?
      make || exit $?
      mv sshpass ../ || exit $?
      popd || exit $?
    fi
    ;;
  *)
    pdie "Unknown OS Identifier: $OS_ID"
    ;;
  esac
fi

## Setup pip
## ======================================================================

if ! "$python" -m pip help >&/dev/null; then
  v "Getting get-pip.py ..."
  if type curl >&/dev/null; then
    curl --output get-pip.py "$get_pip_url" || exit $?
  else
    wget --quiet --timestamping "$get_pip_url" || exit $?
  fi

  v "Running get-pip.py ..."
  "$python" get-pip.py --user || exit $?
fi

## Setup Ansible
## ======================================================================

. ./activate || exit $?

v "Installing modules ..."
if [[ ${#python_modules_pre[@]} -gt 0 ]]; then
  "$python" -m pip install --user --ignore-installed "${python_modules_pre[@]}" || exit $?
fi
"$python" -m pip install --user --ignore-installed "${python_modules[@]}" || exit $?

## ======================================================================

v "Done."
exit 0

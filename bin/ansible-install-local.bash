#!/bin/bash
##
## Ansible: Setup user's local Ansible environment
## Copyright (c) 2017-2019 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
umask 0022

v() {
  echo "$({ tput bold; tput smul; } 2>/dev/null)${0##*/}: $*$(tput sgr0 2>/dev/null)"
}

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <ANSIBLEDIR> [MODULE[=VERSION] ...]"
  echo
  echo "Example to install the latest version:"
  echo "  \$ $0 ~/ansible"
  echo "  ..."
  echo "  \$ source ~/ansible/bin/env-setup"
  echo "  \$ type ansible"
  echo "  ansible is /home/yourname/ansible/bin/ansible"
  echo "  \$ ansible localhost -m ping"
  echo "  ..."
  echo
  echo "Example to install a specific version:"
  echo "  \$ ansible_version=2.2.1.0 $0 ~/ansible"
  echo "  ..."
  exit 1
fi

v "Started."

ansible_root="$1"; shift
if [[ $ansible_root != /* ]]; then
  ansible_root="$PWD/$ansible_root"
fi

python="${python:-python}"
pip="${pip:-pip}"
python_modules=(
  ansible${ansible_version:+==$ansible_version}
  paramiko${paramiko_version:+==$paramiko_version}
  pyyaml${pyyaml_version:+==$pyyaml_version}
  jinja2${jinja2_version:+==$jinja2_version}
  httplib2${httplib2_version:+==$httplib2_version}
  six${six_version:+==$six_version}
  pycrypto${pycrypto_version:+==$pycrypto_version}
  netaddr${netaddr_version:+==$netaddr_version}
  jmespath${jmespath_version:+==$jmespath_version}
  xmltodict${xmltodict_version:+==$xmltodict_version}
  pywinrm${pywinrm_version:+==$pywinrm_version}
  "$@"
)
get_pip_url="${get_pip_uri:-https://bootstrap.pypa.io/get-pip.py}"

echo "Ansible directory: $ansible_root"
echo "Python: $python"
echo "Python modules:"
for module in "${python_modules[@]}"; do
  echo "  $module"
done
echo "get-pip.py: $get_pip_url"

## Check if required component to build modules exist
## ======================================================================

v "Checking C compiler to build binary modules ..."
type gcc || type cc || exit $?

if [[ -f /etc/os-release ]]; then
  v "Checking required packages to build binary modules ..."

  eval "$(sed 's/^\([A-Z]\)/OS_\1/' /etc/os-release)" || exit $?
  case "$OS_ID" in
  debian|ubuntu)
    DPKG_PAGER=cat dpkg -l python-dev libssl-dev libffi-dev libgmp-dev || exit $?
    ;;
  redhat|centos|fedora)
    rpm -q python-devel openssl-devel libffi-devel gmp-devel || exit $?
    ;;
  esac
fi

## ======================================================================

export PATH="$ansible_root/bin:$PATH"
export PYTHONUSERBASE="$ansible_root"
export XDG_CACHE_HOME="$ansible_root/var/cache/xdg"

mkdir -p "$ansible_root/bin" || exit $?
cd "$ansible_root/bin" || exit $?

## Setup pip
## ======================================================================

if ! type "$pip" >&/dev/null; then
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

v "Installing modules ..."
"$pip" install --user --ignore-installed "${python_modules[@]}" || exit $?

## Create env-setup script
## ======================================================================

cat <<EOF >env-setup || exit $?
ansible_root="$ansible_root"
EOF

cat <<'EOF' >>env-setup || exit $?
if [ X"${0##*/}" = X"env-setup" ]; then
  ansible_root=$(cd "${0%/*}/.." && pwd) || return $?
elif [ -n "${BASH_VERSION-}" ]; then
  ansible_root=$(cd "${BASH_SOURCE[0]%/*}"/.. && pwd) || return $?
elif [ -n "$KSH_VERSION" ] && [ -n "${KSH_VERSION#*MIRBSD KSH *}" ]; then
  ansible_root=$(cd "${.sh.file%/*}/.." && pwd) || return $?
else
  ansible_root="$PWD"
fi

python_sitelib=$(echo "$ansible_root"/lib/python*/*)

export PATH="$ansible_root/bin:$PATH"
export PYTHONPATH="$python_sitelib"
EOF

v "Done."
exit 0

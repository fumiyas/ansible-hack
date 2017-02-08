#!/bin/bash
##
## Ansible: Setup user's local Ansible environment
## Copyright (c) 2017 SATOH Fumiyasu @ OSS Technology Corp., Japan
##
## License: GNU General Public License version 3
##

set -u
umask 0022

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <SETUPDIR>"
  exit 1
fi

ansible_root="$1"; shift
if [[ $ansible_root != /* ]]; then
  ansible_root="$PWD/$ansible_root"
fi

python_modules=(
  ansible==2.2.1.0
  paramiko
  pyyaml
  jinja2
  httplib2
  six
  pywinrm
)

export PYTHONUSERBASE="$ansible_root"
export XDG_CACHE_HOME="$ansible_root/var/cache/xdg"

mkdir -p "$ansible_root/bin" || exit 1
cd "$ansible_root/bin" || exit 1
wget --timestamping https://bootstrap.pypa.io/get-pip.py || exit 1
python get-pip.py --user || exit 1

python_sitelib=$(echo "$ansible_root"/lib/python*/*)
export PATH="$ansible_root/bin:$PATH"
export PYTHONPATH="$python_sitelib"

pip install --user --ignore-installed "${python_modules[@]}" || exit 1

cat <<EOF >env-setup
ansible_root="$ansible_root"
EOF

cat <<'EOF' >>env-setup
if [[ -n ${ZSH_VERSION-} ]]; then
  ansible_root=$(cd "${0%/*}/.." && pwd) || return 1
elif [[ -n ${BASH_VERSION-} ]]; then
  ansible_root=$(cd "${BASH_SOURCE[0]%/*}"/.. && pwd) || return 1
fi

python_sitelib=$(echo "$ansible_root"/lib/python*/*)

export PATH="$ansible_root/bin:$PATH"
export PYTHONPATH="$python_sitelib"
EOF

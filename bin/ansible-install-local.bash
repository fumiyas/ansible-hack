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
  echo "  \$ ansible_core_version='<2.12' $0 ~/ansible"
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
    if "$python_try" -c 'import sys; sys.exit(sys.version_info[0]<3)' >/dev/null 2>&1; then
      python="$python_try"
      break
    fi
  done
fi
if [[ -z ${python-} ]]; then
  pdie "Python3 not found"
fi

python_ver=$(
"$python" <<'EOF'
import sys
print('.'.join((str(x) for x in sys.version_info)))
EOF
)
python_ver_int=$(
"$python" <<'EOF'
import sys
print('%d%02d%02d' % sys.version_info[:3])
EOF
)

python_modules_pre=()
if ! "$python" -m wheel --help >/dev/null 2>&1; then
  python_modules_pre+=(
    "wheel${wheel_version-}"
  )
fi

if [[ $python_ver_int -lt 30800 && -z ${ansible_version-} ]];then
  ansible_core_version='<2.12'
fi

python_modules=(
  "ansible${ansible_version-}"
  "ansible-core${ansible_core_version-}"
  "pyyaml${pyyaml_version-}"
  "jinja2${jinja2_version-}"
  ## cryptography 3.4+ requires Rust compiler
  "cryptography${cryptography_version-}${cryptography_version:-<3.4}"
  "httplib2${httplib2_version-}"
  "six${six_version-}"
  "netaddr${netaddr_version-}"
  "jmespath${jmespath_version-}"
  "xmltodict${xmltodict_version-}"
  "pywinrm${pywinrm_version-}"
  "$@"
)

if [[ $python_ver_int -ge 30700 ]];then
  get_pip_url="${get_pip_uri:-https://bootstrap.pypa.io/get-pip.py}"
else
  get_pip_url="${get_pip_uri:-https://bootstrap.pypa.io/pip/3.6/get-pip.py}"
fi

sshpass_src_base_url="https://sourceforge.net/projects/sshpass/files/sshpass"
sshpass_version="${sshpass_version:-1.10}"

if [[ $(id -u) -eq 0 ]]; then
  sudo=
else
  sudo='sudo'
fi

## ----------------------------------------------------------------------

eval "$(sed 's/^\([A-Z]\)/OS_\1/' /etc/os-release)" || exit $?

if [[ -z ${OS_VERSION_ID-} ]]; then
  ## Debian unstable (sid)
  OS_VERSION_ID="9999"
fi

OS_VERSION_MAJOR="${OS_VERSION_ID%%.*}"

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

v "Checking required packages to build binary modules ..."
case "$OS_ID" in
debian|ubuntu)
  buildrequires=(gcc libssl-dev libffi-dev libgmp-dev python3-dev)
  if [[ -n ${ANSIBLE_INSTALL_LOCAL_INSTALL_BUILDREQUIRES-} ]]; then
    $sudo env DEBIAN_FRONTEND=noninteractive apt-get install --yes "${buildrequires[@]}" || exit $?
  fi
  dpkg --list --no-pager "${buildrequires[@]}" || true
  dpkg --status "${buildrequires[@]}" >/dev/null || exit $?
  ;;
redhat|almalinux|rocky|centos|fedora)
  buildrequires=(gcc openssl-devel libffi-devel gmp-devel)
  if [[ ${python##*/} == platform-python && $OS_VERSION_MAJOR -eq 8 ]]; then
    buildrequires+=(platform-python-devel)
  else
    buildrequires+=(python3-devel)
  fi
  if [[ -n ${ANSIBLE_INSTALL_LOCAL_INSTALL_BUILDREQUIRES-} ]]; then
    $sudo yum install --assumeyes "${buildrequires[@]}" || exit $?
  fi
  rpm -q --qf '%{name}-%{version}-%{release}\n' "${buildrequires[@]}" \
  |sed -n -e '/ /{s/^/ERROR: /;H}' -e '/ /!p' -e '${x;s/^\n//;p}' \
  || exit $? \
  ;
  ;;
esac

v "Checking C compiler to build binary modules ..."
type gcc || type cc || exit $?

## ======================================================================

export PATH="$ansible_root/bin:$PATH"
export PYTHONUSERBASE="$ansible_root"
export PYTHONDONTWRITEBYTECODE="set"
export PYTHONUNBUFFERED="set"
export PYTHON_KEYRING_BACKEND="keyring.backends.null.Keyring"
export PIP_DISABLE_PIP_VERSION_CHECK="on"
export PIP_PROGRESS_BAR="off"
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
  redhat|almalinux|rocky|centos|fedora)
    if [[ $OS_VERSION_MAJOR -ne 8 ]] || [[ $OS_ID == fedora ]]; then
      v "Downloading sshpass binary in *.rpm package ..."
      rm -f sshpass-[0-9]*.rpm || exit $?
      if type dnf >/dev/null 2>&1; then
        dnf download sshpass || exit $?
      else
        yumdownloader --disablerepo=\* --enablerepo=extras sshpass || exit $?
      fi
      rpm2cpio sshpass-[0-9]*.rpm |cpio -id ./usr/bin/sshpass || exit $?
      mv ./usr/bin/sshpass ./ || exit $?
      rmdir ./usr/bin ./usr || exit $?
      rm -f sshpass-[0-9]*.rpm || exit $?
    else
      v "Checking curl and make commands to build sshpass binary ..."
      type curl || exit $?
      type make || exit $?
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
    curl \
      --silent \
      --show-error \
      --location \
      --output get-pip.py \
      "$get_pip_url" \
    || exit $?
  else
    wget --quiet --timestamping "$get_pip_url" || exit $?
  fi

  v "Running get-pip.py ..."
  "$python" get-pip.py --user || exit $?
fi

## Setup Ansible
## ======================================================================

. ./activate || exit $?

pip() {
  ## Use --no-cache-dir option instead of PIP_NO_CACHE_DIR environment
  ## for workaround a issue: https://github.com/pypa/pip/issues/5852
  command "$python" -m pip --no-cache-dir "$@"
}

v "Installing modules ..."
if [[ ${#python_modules_pre[@]} -gt 0 ]]; then
  pip install --user --ignore-installed "${python_modules_pre[@]}" || exit $?
fi
pip install --user --ignore-installed "${python_modules[@]}" || exit $?

## ======================================================================

v "Done."
exit 0

#!/bin/bash
#
set -eou pipefail

# If the variable $DEBUG is set, print all shell commands executed
if [ -n "${DEBUG:-}" ]; then set -x; fi

readonly binary=cli
readonly purpose=install
readonly install_dir=/usr/local/bin
readonly github_org=afiune
readonly github_repo=go-release
readonly github_releases="https://github.com/${github_org}/${github_repo}/releases"

usage() {
  local _cmd
  _cmd="$(basename "${0}")"
  cat <<USAGE
${_cmd}: Installs the '${binary}' tool.

USAGE:
    ${_cmd} [FLAGS]

FLAGS:
    -h    Prints help information
    -v    Specifies a version (ex: 0.1.0)
    -t    Specifies the target of the program to download (default: linux-amd64)
USAGE
}

main() {
  version=""

  # Parse command line flags and options.
  while getopts "c:hv:t:" opt; do
    case "${opt}" in
      h)
        usage
        exit 0
        ;;
      v)
        version="${OPTARG}"
        ;;
      t)
        target="${OPTARG}"
        ;;
      \?)
        echo "" >&2
        usage >&2
        exit_with "Invalid option" 1
        ;;
    esac
  done

  log "Installing the '${binary}' tool"
  create_workdir
  check_platform
  download_archive "$version" "$target"
  verify_archive
  extract_archive
  install_cli
  print_cli_version
  log "The '${binary}' tool has been successfully installed."
}

log() {
  echo "--> ${purpose:-info}: $1"
}

warn() {
  echo "xxx ${purpose:-warn}: $1" >&2
}

exit_with() {
  warn "$1"
  exit "${2:-10}"
}

create_workdir() {
  if [ -d /var/tmp ]; then
    local _tmp=/var/tmp
  else
    local _tmp=/tmp
  fi

  workdir="$(mktemp -d -p "$_tmp" 2> /dev/null || mktemp -d "${_tmp}/${binary}.XXXX")"
  # add a trap to clean up work directory
  trap 'code=$?; rm -rf $workdir; exit $code' INT TERM EXIT
  cd "${workdir}"
}

check_platform() {
  local _ostype
  _ostype="$(uname -s)"

  case "${_ostype}" in
    Darwin|Linux)
      sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
      arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
      ;;
    *)
      exit_with "unable to determine OS platform type: ${_ostype}" 2
      ;;
  esac

  case "${sys}" in
    darwin)
      ext=zip
      shasum_cmd="shasum -a 256"
      ;;
    linux)
      ext=tar.gz
      shasum_cmd="sha256sum"
      ;;
    *)
      exit_with "unable to determine system type, perhaps is not supported: ${sys}" 3
      ;;
  esac

  # The following architectures match our cross-platform build process
  # https://golang.org/doc/install/source#environment
  case "${arch}" in
    x86_64)
      arch=amd64
      ;;
   i686)
      arch=386
      ;;
    *)
      exit_with "architecture not supported: ${arch}" 3
      ;;
  esac

  if [ -z "${target:-}" ]; then
    target="${sys}-${arch}"
  fi
}

download_archive() {
  local _version="${1:-latest}"
  local -r _target="${2:?}"
  local url

  if [ "$_version" == "latest" ]; then
    url="${github_releases}/latest/download/${binary}-${_target}.${ext}"
  else
    url="${github_releases}/download/${_version}/${binary}-${_target}.${ext}"
  fi

  download_file "${url}" "${workdir}/${binary}-${_version}.${ext}"
  download_file "${url}.sha256sum" "${workdir}/${binary}-${_version}.${ext}.sha256sum"

  archive="${binary}-${_target}.${ext}"
  sha_file="${binary}-${_target}.${ext}.sha256sum"

  mv -v "${workdir}/${binary}-${_version}.${ext}" "${archive}"
  mv -v "${workdir}/${binary}-${_version}.${ext}.sha256sum" "${sha_file}"
}

verify_archive() {
  log "Verifying the shasum digest matches the downloaded archive"
  ${shasum_cmd} -c "${sha_file}"
}

extract_archive() {
  log "Extracting ${archive}"
  case "${ext}" in
    tar.gz)
      archive_dir="${archive%.tar.gz}"
      mkdir "${archive_dir}"
      zcat "${archive}" | tar --extract --directory "${archive_dir}" --strip-components=1

      ;;
    zip)
      archive_dir="${archive%.zip}"
      unzip -j "${archive}" -d "${archive_dir}"
      ;;
    *)
      exit_with "[extract] Unknown file extension: ${ext}" 4
      ;;
  esac
}

install_cli() {
  log "Installing $binary into $install_dir"
  mkdir -pv "$install_dir"
  _binary_with_target="${binary}-${target}"
  install -v "${archive_dir}/${_binary_with_target}" "${install_dir}/${binary}"
}

print_cli_version() {
  info "Verifying installed ${binary} version"
  "${install_dir}/${binary}" version
}

download_file() {
  local _url="${1}"
  local _dst="${2}"
  local _code
  local _wget_extra_args=""
  local _curl_extra_args=""

  # try to download with wget
  if command -v wget > /dev/null; then
    log "Downloading via wget: ${_url}"

    wget -q -O "${_dst}" "${_url}"
    _code="$?"

    if [ $_code -eq 0 ]; then
      return 0
    else
      warn "wget failed to download file, trying to download with curl"
    fi
  fi

  # try to download with curl
  if command -v curl > /dev/null; then
    log "Downloading via curl: ${_url}"

    curl -sSfL "${_url}" -o "${_dst}"
    _code="$?"

    if [ $_code -eq 0 ]; then
      return 0
    else
      warn "curl failed to download file"
    fi
  fi

  # wget and curl have failed, inform the user
  exit_with "Required: SSL-enabled 'curl' or 'wget' on PATH with" 6
}

main "$@" || exit 99

#!/bin/bash
#
# Name::        release.sh
# Description:: Use this script to prepare a new release on Github,
#               the automation will build cross-platform binaries,
#               compress all generated targets, generate shasum
#               hashes, and create a GH tag like v0.1.0 (using the
#               VERSION file inside the cli/ directory)
# Author::      Salim Afiune Maya (<salim@afiunemaya.com.mx>)
#
set -eou pipefail

readonly binary=cli
readonly github_org=afiune
readonly github_repo=go-release
readonly github_releases="https://github.com/${github_org}/${github_repo}/releases"
readonly version=$(cat VERSION)
readonly targets=(
  ${binary}-darwin-386
  ${binary}-darwin-amd64
  ${binary}-windows-386.exe
  ${binary}-windows-amd64.exe
  ${binary}-linux-386
  ${binary}-linux-amd64
)

readonly purpose=release
source logging.sh

main() {
  log "Preparing release v$version"
  prerequisites
  build_cli_cross_platform
  compress_targets
  generate_shasums
  create_git_tag
}

create_git_tag() {
  local _tag="v$version"
  log "Creating github tag: $_tag"
  git tag "$_tag"
  git push origin "$_tag"
  log "Go to ${github_releases} and upload all files from 'bin/'"
}

prerequisites() {
  local _branch=$(git rev-parse --abbrev-ref HEAD)
  if [ "$_branch" != "master" ]; then
    warn "Releases must be generated from the 'master' branch. (current $_branch)"
    warn "Switch to the master branch and try again."
    exit 127
  fi

  if ! command -v "gox" > /dev/null 2>&1; then
    warn "Installing 'gox' command"
    go get github.com/mitchellh/gox
  fi
}

clean_cache() {
  log "Cleaning cache bin/ directory"
  rm -rf bin/*
}

build_cli_cross_platform() {
  clean_cache
  log "Building cross-platform binaries"
  gox -output="bin/${binary}-{{.OS}}-{{.Arch}}" \
      -os="darwin linux windows" \
      -arch="amd64 386" \
      "github.com/${github_org}/${github_repo}"
  echo
}

generate_shasums() {
  ( cd bin/
    local _compressed
    log "Generating sha256sum Hashes"
    for target in ${targets[*]}; do

      if [[ "$target" =~ linux ]]; then
	_compressed="$target.tar.gz"
      else
	_compressed="$target.zip"
      fi

      log "bin/$_compressed.sha256sum"
      shasum -a 256 $_compressed > $_compressed.sha256sum

    done
  )
}

# compress_targets will compress all targets and remove the raw
# binaries (already compressed), this is a release so we don't
# need the raw binaries anymore.
compress_targets() {
  log "Compressing target binaries"
  local _target_with_ext
  for target in ${targets[*]}; do
    if [[ "$target" =~ linux ]]; then
      _target_with_ext="bin/${target}.tar.gz"
      log $_target_with_ext
      tar -czvf "${_target_with_ext}" "bin/${target}" 2>/dev/null
    else
      _target_with_ext="bin/${target}.zip"
      log $_target_with_ext
      zip "${_target_with_ext}" "bin/${target}" >/dev/null
    fi
    rm -f "bin/${target}"
  done
}

main || exit 99

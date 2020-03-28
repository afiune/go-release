#!/bin/bash

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

readonly SH_OK=0
readonly SH_NG=1

readonly LF=$'\n'

__gid=0

GLOBAL=()

# return values
RV1=
RV2=

new_gid() {
  RV1=$__gid
  __gid=$((__gid + 1))
}

echo_e() {
  echo "$@" >&2
}

echo_kv_e() {
  echo "$1 ($2)" >&2
}

debug_e() {
  # printf "$@" >&2
  :
}

panic() {
  echo "PANIC $@" | cat -A >&2
  exit 1
}

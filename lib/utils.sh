_to_hex() {
  od --address-radix=n --format=x1 --output-duplicates \
    | tr " " "\n" \
    | grep -v '^$'
}

read_stdin_all() {
  RV1="$(cat)"
}

# for debug
puts_fn() {
  local fn_name="$1"; shift

  # echo_e "  |-->> ${fn_name}"
}

to_hex() {
  local str="$1"; shift

  local hexlines="$(
    printf -- "$str" | _to_hex
  )"
  RV1="${hexlines}${LF}"
}

from_hex() {
  local hexlines="$1"; shift

  local c=

  str=""
  while read -r c; do
    if [ "$c" = "0a" ]; then
      str="${str}${LF}"
    else
      str="${str}$(printf "\x${c}")"
    fi
  done < <(printf "$hexlines")

  RV1="$str"
}

count_lines() {
  local text="$1"; shift

  local n="$(echo "${text}" | wc -l)"
  local lastline="$(echo "$text" | tail -1)"

  if [ "$lastline" = "" ]; then
    # ignore last empty line
    echo $((n - 1))
  else
    echo $n
  fi
}

bytesize_hex() {
  local hexstr="$1"; shift

  count_lines "$hexstr"
}

bytesize() {
  local str="$1"; shift

  local hexstr=

  to_hex "$str"
  hexstr="$RV1"

  bytesize_hex "$hexstr"
}

line_at() {
  local text="$1"; shift
  local i="$1"; shift

  local lineno=$((i + 1))

  echo "$text" | awk "NR == ${lineno} { print }"
}

index_hex() {
  local hexstr="$1"; shift
  local hexc="$1"; shift
  local pos_start="$1"; shift

  local size=$(bytesize_hex "$hexstr")

  local i=$pos_start
  local line=
  while [ $i -lt $size ]; do
    line="$(line_at "$hexstr" $i)"

    if [ "$line" = "$hexc" ]; then
      echo $i
      return
    fi
    i=$((i + 1))
  done

  echo -1
}

substring_hex() {
  local hexlines="$1"; shift
  local from="$1"; shift
  local to="$1"; shift

  local hexlines2="$(
    printf "$hexlines" | awk "${from} <= (NR - 1) && (NR - 1) < ${to} { print }"
  )"

  RV1="$hexlines2${LF}"
  #=> RV1
}

is_digit_char_hex() {
  local hexc="$1"; shift

  case "$hexc" in
    "30" | "31" | "32" | "33" | "34" | "35" | "36" | "37" | "38" | "39" )
      return $SH_OK
  ;; * )
       return $SH_NG
  esac
}

find_non_digit_index_hex() {
  local hexlines="$1"; shift
  local pos_start="$1"; shift

  local line=
  local size=$(echo "$hexlines" | wc -l)
  size=$((size - 1))
  local i=$pos_start
  while [ $i -lt $size ]; do
    line="$(line_at "$hexlines" $i)"
    if [ "$line" = "2d" ] || is_digit_char_hex "$line"; then
      : is digit
    else
      RV1=$i
      return
    fi
    i=$((i + 1))
  done

  RV1=$i # TODO EOF の場合
}

# --------------------------------
# list

readonly RE_NODE_INT="^int:(.+)"
readonly RE_NODE_STR="^str:(.+)"
readonly RE_NODE_LIST="^list:(.+)"

new_list() {
  new_gid
  local self_=$RV1
  GLOBAL[$self_]=""

  RV1=$self_
}

Node_get() {
  local node="$1"; shift

  if   [[ "$node" =~ $RE_NODE_INT  ]]; then
    RV1="int"
    RV2=${BASH_REMATCH[1]}
  elif [[ "$node" =~ $RE_NODE_STR  ]]; then
    RV1="str"
    RV2="${BASH_REMATCH[1]}"
  elif [[ "$node" =~ $RE_NODE_LIST ]]; then
    RV1="list"
    RV2=${BASH_REMATCH[1]}
  else
    panic "unexpected kind (${node})"
  fi
}

Node_get_val() {
  local node="$1"; shift

  Node_get "$node"
  printf -- "$RV2"
}

List_size() {
  local self_="$1"; shift

  count_lines "${GLOBAL[self_]}"
}

List_add_node() {
  local self_="$1"; shift
  local node="$1"; shift

  local current="${GLOBAL[self_]}"

  GLOBAL[self_]="${current}${node}${LF}"
}

List_add_int() {
  local self_="$1"; shift
  local rawval="$1"; shift

  List_add_node $self_ "int:${rawval}"
}

List_add_str() {
  local self_="$1"; shift
  local rawval="$1"; shift

  List_add_node $self_ "str:${rawval}"
}

List_add_list() {
  local self_="$1"; shift
  local rawval="$1"; shift

  List_add_node $self_ "list:${rawval}"
}

List_rest() {
  local self_="$1"; shift

  local newlist_=
  new_list
  newlist_=$RV1

  local i=1
  local size=$(List_size $self_)
  local node=
  while [ $i -lt $size ]; do
    node="$(List_get_node $self_ $i)"
    List_add_node $newlist_ "$node"
    i=$((i + 1))
  done

  RV1=$newlist_
}

List_get_node() {
  local self_="$1"; shift
  local i="$1"; shift

  local lines="${GLOBAL[self_]}"
  line_at "$lines" $i
}

List_get_str() {
  local self_="$1"; shift
  local i="$1"; shift

  local lines="${GLOBAL[self_]}"
  local node="$(line_at "$lines" $i)"
  Node_get_val "$node"
}

List_get_list() {
  local self_="$1"; shift
  local i="$1"; shift

  local lines="${GLOBAL[self_]}"
  local node="$(line_at "$lines" $i)"
  Node_get_val "$node"
}

List_add_all() {
  local self_="$1"; shift
  local other_="$1"; shift

  local i=0
  local size=$(List_size $other_)
  local node=
  while [ $i -lt $size ]; do
    node="$(List_get_node $other_ $i)"
    List_add_node $self_ "$node"
    i=$((i + 1))
  done
}

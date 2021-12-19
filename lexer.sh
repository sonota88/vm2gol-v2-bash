set -o errexit
set -o pipefail
set -o nounset

print_this_dir() {
  (
    cd "$(dirname "$0")"
    pwd
  )
}

source $(print_this_dir)/lib/common.sh
source $(print_this_dir)/lib/utils.sh
source $(print_this_dir)/lib/json.sh

SRC_HEX_ARRAY=()

set_src_hex_array() {
  local src_hex="$1"; shift

  SRC_HEX_ARRAY=()
  while read -r line; do
    # SRC_HEX_ARRAY=("${SRC_HEX_ARRAY[@]}" "$line") # slow
    SRC_HEX_ARRAY+=("$line")
  done < <(printf "$src_hex")
}

print_token() {
  local lineno="$1"; shift
  local kind="$1"; shift
  local val="$1"; shift

  printf "["
  printf $lineno
  printf ", "
  printf '"'
  printf $kind
  printf '"'
  printf ", "
  printf '"'
  printf -- "$val"
  printf '"'
  printf "]"
  printf "\n"
}

is_kw() {
  local str="$1"; shift

  case "$str" in
    "func" | "var" | "set" | "call" | "call_set" | "return" | "while" | "case" | "when" | "_cmt" )
      return $SH_OK
    ;; *)
      return $SH_NG
    ;;
  esac
}

is_sym() {
  local c0="$1"; shift

  case "$c0" in
    #(      )      {      }      ;      =      ,      +      *
    "28" | "29" | "7b" | "7d" | "3b" | "3d" | "2c" | "2b" | "2a" )
      return $SH_OK
  ;; * )
       return $SH_NG
  esac
}

is_ident_char_hex() {
  local hexc="$1"; shift

  if [ "$hexc" = "5f" ]; then
    # _
    return $SH_OK
  elif is_digit_char_hex "$hexc"; then
    # 0..9
    return $SH_OK
  elif [[ "$hexc" =~ 6[123456789abcdef] ]]; then
    # a..o
    return $SH_OK
  elif [[ "$hexc" =~ 7[0123456789a] ]]; then
    # p..z
    return $SH_OK
  else
    return $SH_NG
  fi
}

find_non_ident_index_hex_array() {
  local pos_start="$1"; shift

  local hexchar=
  local bsize=${#SRC_HEX_ARRAY[@]}

  local i=$pos_start
  while [ $i -lt $bsize ]; do
    hexchar=${SRC_HEX_ARRAY[i]}

    if is_ident_char_hex "$hexchar"; then
      : is digit
    else
      RV1=$i
      return
    fi
    i=$((i + 1))
  done

  RV1=-1
}

lex() {
  read_stdin_all
  local src="$RV1"

  local src_hex=; to_hex "$src"
  src_hex="$RV1"

  set_src_hex_array "$src_hex"
  SRC_HEX_ARRAY+=("00") # for last c1

  local pos=0
  local bsize=$(bytesize "$src")
  local rest=
  local rest_hex=
  local temp=
  local pos_delta=
  local lineno=1
  local c0=
  local c1=

  while [ $pos -lt $bsize ]; do
    c0="${SRC_HEX_ARRAY[pos]}"
    c1="${SRC_HEX_ARRAY[pos + 1]}"

    if [ "$c0" = "20" ]; then
      pos=$((pos + 1))

    elif [ "$c0" = "0a" ]; then
      pos=$((pos + 1))
      lineno=$((lineno + 1))

      if [ $((lineno % 10)) -eq 0 ]; then
        debug_e "${pos} / ${bsize}\n"
      fi

    elif [ "${c0}${c1}" = "3d3d" ] ; then
      pos=$((pos + 2))
      print_token $lineno "sym" "=="

    elif [ "${c0}${c1}" = "213d" ] ; then
      pos=$((pos + 2))
      print_token $lineno "sym" "!="

    elif is_sym "$c0"; then
      pos=$((pos + 1))
      print_token $lineno "sym" "$(printf "\x${c0}")"

    elif [ "$c0" = "22" ]; then # "
      local end_dq_idx=$(
        index_hex "$src_hex" "22" $((pos + 1))
      )

      substring_hex "$src_hex" $((pos + 1)) $end_dq_idx
      local temp_hex="$RV1"

      from_hex "$temp_hex"
      temp="$RV1"

      local len=$(( end_dq_idx - (pos + 1) ))

      pos=$((pos + len + 2))

      print_token $lineno "str" "$temp"

    elif [ "${c0}${c1}" = "2f2f" ]; then # //
      local lf_idx=$(
        index_hex "$src_hex" "0a" $pos
      )

      pos=$((lf_idx))

    elif [ "$c0" = "2d" ] || is_digit_char_hex "$c0"; then
      find_non_digit_index_hex "$src_hex" $pos
      non_digit_index=$RV1

      substring_hex "$src_hex" $pos $non_digit_index
      hex1="$RV1"

      from_hex "$hex1"
      n="$RV1"
      pos=$non_digit_index
      print_token $lineno "int" "$n"

    elif is_ident_char_hex "$c0"; then
      find_non_ident_index_hex_array $pos
      non_ident_index=$RV1

      substring_hex "$src_hex" $pos $non_ident_index
      hex1="$RV1"

      from_hex "$hex1"
      temp="$RV1"

      pos=$non_ident_index

      if is_kw "$temp"; then
        print_token $lineno "kw" "$temp"
      else
        print_token $lineno "ident" "$temp"
      fi

    else
      panic "unexpected pattern ($lineno) ($pos) ($rest)"
    fi
  done
}

lex

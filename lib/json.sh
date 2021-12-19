print_indent() {
  local lv="$1"; shift

  while [ 0 -lt $lv ]; do
    printf "  "
    lv=$((lv - 1))
  done
}

_json_print_node() {
  local node="$1"; shift
  local lv="$1"; shift

  Node_get "$node"
  local node_type="$RV1"
  local val="$RV2"

  print_indent $lv

  case "$node_type" in
    "int" )
      printf -- $val
  ;; "str" )
      printf '"'
      printf -- "$val"
      printf '"'
  ;; "list" )
      _json_print_list $val $lv
  ;; * )
      panic "unexpected node_type ($node_type)"
  ;;
  esac
}

_json_print_list() {
  local list_="$1"; shift
  local lv="$1"; shift

  local i=-1

  printf "[\n"

  local num_items=$(List_size $list_)

  while read -r line; do
    i=$((i + 1))
    if [ "$line" = "" ]; then
      continue
    fi

    _json_print_node "$line" $((lv + 1))

    if [ $i -lt $((num_items - 1)) ]; then
      printf ","
    fi
    printf "\n"
  done < <(printf "${GLOBAL[list_]}")

  print_indent $lv
  printf "]"
}

json_print() {
  local list_="$1"; shift

  _json_print_list $list_ 0
}

JSON_HEX_ARRAY=()

set_json_hex_array() {
  local json_hex="$1"; shift

  JSON_HEX_ARRAY=()
  while read -r line; do
    # JSON_HEX_ARRAY=("${JSON_HEX_ARRAY[@]}" "$line") # slow
    JSON_HEX_ARRAY+=("$line")
  done < <(printf "$json_hex")
}

index_hex_array() {
  local target="$1"; shift
  local pos_start="$1"; shift

  local num_chars=${#JSON_HEX_ARRAY[@]}

  local i=$pos_start
  while [ $i -lt $num_chars ]; do
    if [ "${JSON_HEX_ARRAY[i]}" = "$target" ]; then
      echo $i
      return
    fi
    i=$((i + 1))
  done

  echo -1
}

_json_parse() {
  local json_hex="$1"; shift
  local pos_start="$1"; shift

  local pos=$((pos_start + 1)) # skip first [
  local lineno=1
  local bsize=$(bytesize_hex "$json_hex")
  local str=

  local c0=

  new_list
  local list_=$RV1

  local list_child_=

  if [ 1000 -le $bsize ]; then
    debug_e "[ ${pos}/${bsize} "
  fi

  while [ $pos -lt $bsize ]; do
    c0="${JSON_HEX_ARRAY[pos]}"

    if [ "$c0" = "20" ]; then # SPC
      pos=$((pos + 1))

    elif [ "$c0" = "5b" ]; then # [
      _json_parse "$json_hex" $pos
      list_child_=$RV1
      pos=$RV2

      List_add_list $list_ $list_child_

    elif [ "$c0" = "5d" ]; then # ]
      pos=$((pos + 1))
      if [ 1000 -le $bsize ]; then
        debug_e "] "
      fi
      break

    elif [ "$c0" = "0a" ]; then # LF
      pos=$((pos + 1))
      lineno=$((lineno + 1))

    elif [ "$c0" = "2c" ]; then # ,
      pos=$((pos + 1))

    elif [ "$c0" = "22" ]; then # "
      local end_dq_idx=$(
        index_hex_array "22" $((pos + 1))
      )

      substring_hex "$json_hex" $((pos + 1)) $end_dq_idx
      local temp_hex="$RV1"

      from_hex "$temp_hex"
      str="$RV1"
      List_add_str $list_ "$str"

      local len=$(( end_dq_idx - (pos + 1) ))

      pos=$((pos + len + 2))

    elif [ "$c0" = "2d" ] || is_digit_char_hex "$c0"; then

      find_non_digit_index_hex "$json_hex" $pos
      local non_digit_index=$RV1

      substring_hex "$json_hex" $pos $non_digit_index
      hex1="$RV1"

      from_hex "$hex1"
      n=$RV1

      pos=$non_digit_index
      List_add_int $list_ $n

    else
      panic "unexpected pattern ($lineno) ($pos/$bsize)"
    fi
  done

  RV1=$list_
  RV2=$pos
}

json_parse() {
  local json="$1"; shift

  to_hex "$json"
  local json_hex="$RV1"

  set_json_hex_array "$json_hex"
  _json_parse "$json_hex" 0
}

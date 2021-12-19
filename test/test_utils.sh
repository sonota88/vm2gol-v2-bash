set -o errexit
set -o pipefail
set -o nounset

print_this_dir() {
  (
    cd "$(dirname "$0")"
    pwd
  )
}

source $(print_this_dir)/../lib/common.sh
source $(print_this_dir)/../lib/utils.sh

assert_i() {
  local exp="$1"; shift
  local act="$1"; shift
  local msg="$1"; shift

  if [ $act -eq $exp ]; then
    : OK
  else
    echo_e $msg
    echo_e "exp: $exp"
    echo_e "act: $act"
    exit 1
  fi
}

assert_s() {
  local exp="$1"; shift
  local act="$1"; shift
  local msg="$1"; shift

  if [ "$act" = "$exp" ]; then
    : OK
  else
    echo_e $msg
    # echo "exp: $exp" | cat -A >&2
    # echo "act: $act" | cat -A >&2
    echo "exp: ($exp)" >&2
    echo "act: ($act)" >&2
    exit 1
  fi
}

test_to_hex() {
  local str="a
bあcd"
  local hexstr=; to_hex "$str"
  hexstr="$RV1"
  assert_s "61
0a
62
e3
81
82
63
64
" \
    "$hexstr" "to_hex 1"
}

test_from_hex() {
  local hexstr=

  hexstr="61
0a
62
e3
81
82
63
64
$"
  
  local str=
  {
    from_hex "$hexstr"
    str="$RV1"
  }

  assert_s "a
bあcd" \
    "$str" "from_hex 1"

  hexstr="0a
$"
  
  local str=
  {
    from_hex "$hexstr"
    str="$RV1"
  }
  
  assert_s "$LF" "$str" "from_hex 2"
}

test_count_lines() {
  local text=
  local n=

  text="a
b"
  n=$(count_lines "$text")
  assert_i 2 $n "count_lines 1"

  text="a
b
"
  n=$(count_lines "$text")
  assert_i 2 $n "count_lines 2"
}

test_bytesize() {
  local str="a
bあcd"
  local bsize=$(bytesize "$str")
  assert_i 8 $bsize "bytesize 1"
}

test_line_at() {
  local text="aa
bb
cc
dd
"

  local line=

  line="$(line_at "$text" 0)"
  assert_s "aa" "$line" "line_at 1"

  line="$(line_at "$text" 3)"
  assert_s "dd" "$line" "line_at 2"

  text="aa
bb"

  local line=

  line="$(line_at "$text" 1)"
  assert_s "bb" "$line" "line_at 3"
}

test_char_at() {
  local c=
  {
    char_at "fdsa" 1
    c="$RV1"
  }

  assert_s "d" "$c" "char_at 1"
}

test_index() {
  local i=

  i=$(index "fdsa" "d" 0)
  assert_i 1 $i "index 1"

  i=$(index "fdsa" "a" 0)
  assert_i 3 $i "index 2"

  i=$(index "fdsa" "x" 0)
  assert_i -1 $i "index 3"

  i=$(index "a
bあcd" "c" 0)
  assert_i 6 $i "index 4"

  echo_e "===="
  i=$(index "a
b" "$LF" 0)
  assert_i 1 $i "index 5"

  i=$(index "adsa" "a" 1)
  assert_i 3 $i "index: start index is non-zero"
}

test_substring() {
  local str="a
bあcd"
  local act=
  {
    substring "$str" 2 7
    act="$RV1"
  }
  assert_s "bあc" "$act" "substring 1"

  str="a
bあcd"

  local act=
  {
    substring "$str" 1 8
    act="$RV1"
  }

  assert_s "
bあcd" \
    "$act" "substring 2"
}

test_to_hex
test_from_hex
test_count_lines
test_bytesize
test_line_at
test_char_at
test_index
test_substring

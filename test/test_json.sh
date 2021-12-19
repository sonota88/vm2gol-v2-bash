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
source $(print_this_dir)/../lib/json.sh

test_01() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  json_print $xs_
}

test_02() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  List_add_int $xs_ 1

  json_print $xs_
}

test_03() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  List_add_str $xs_ "fdsa"

  json_print $xs_
}

test_04() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  List_add_int $xs_ -123

  json_print $xs_
}

test_05() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  List_add_int $xs_ 123
  List_add_str $xs_ "fdsa"

  json_print $xs_
}

test_06() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  local xs_child_=
  {
    new_list
    xs_child_=$RV1
  }

  list_add_list $xs_ $xs_child_

  json_print $xs_
}

test_07() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  local xs_child_=
  {
    new_list
    xs_child_=$RV1
  }

  List_add_int $xs_child_ 2
  List_add_str $xs_child_ "b"

  List_add_int $xs_ 1
  List_add_str $xs_ "a"
  list_add_list $xs_ $xs_child_
  List_add_int $xs_ 3
  List_add_str $xs_ "c"

  json_print $xs_
}

test_08() {
  local xs_=
  {
    new_list
    xs_=$RV1
  }

  List_add_str $xs_ "漢字"

  json_print $xs_
}

test_json() {
  read_stdin_all
  local json="$RV1"

  local xs_=

  {
    json_parse "$json"
    xs_=$RV1
  }

  json_print $xs_
}

# test_01
# test_02
# test_03
# test_04
# test_05
# test_06
# test_07
# test_08

test_json

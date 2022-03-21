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

readonly RE_LINE="^(.+)
"

ts=()
ti=0
pos=

read_tokens() {
  read_stdin_all
  local tokens_src="$RV1"

  local num_lines=$(count_lines "$tokens_src")

  local line=
  while read -r line; do
    if [ $((ti % 50)) -eq 0 ]; then
      debug_e "$ti / ${num_lines}\n"
    fi

    if [ "$line" = "" ]; then
      continue
    fi

    json_parse "$line"
    t_=$RV1

    ts[$ti]=$t_
    ti=$((ti + 1))
  done < <(echo "$tokens_src")
}

# --------------------------------

peek() {
  local offset="$1"; shift

  local _pos=$((pos + offset))

  local ti_=${ts[_pos]}
  local t="${GLOBAL[ti_]}"

  echo "$t"
}

# increment position
incr_pos() {
  pos=$((pos + 1))
}

Token_get_kind() {
  local t="$1"; shift
  local node="$(line_at "$t" 1)"
  Node_get_val "$node"
}

Token_get_val() {
  local t="$1"; shift
  local node="$(line_at "$t" 2)"
  Node_get_val "$node"
}

consume() {
  local val_e="$1"; shift

  local t="$(peek 0)"
  local val_a="$(Token_get_val "$t")"

  if [ "$val_a" != "$val_e" ]; then
    panic "consume: unexpected token: exp ($val_e) act ($val_a)"
  fi

  incr_pos
}

# --------------------------------

_parse_expr_factor() {
  local t="$(peek 0)"
  local t_kind="$(Token_get_kind "$t")"
  local node=

  case "$t_kind" in
    int )
      incr_pos
      local n=$(Token_get_val "$t")
      node="int:${n}"
  ;; ident )
      incr_pos
      local str=$(Token_get_val "$t")
      node="str:${str}"
  ;; sym )
      consume "("
      parse_expr
      node="$RV1"
      consume ")"
  ;; * )
      panic "parse_expr: invalid kind ($t_kind)"
  esac

  RV1="$node"
}

_is_binop() {
  local t="$(peek 0)"
  local t_val="$(Token_get_val "$t")"

  case "$t_val" in
    "+" | "*" | "==" | "!=" )
      return $SH_OK
  ;; * )
      return $SH_NG
  esac
}

parse_expr() {
  # puts_fn "parse_expr"

  local expr_node=
  local expr_=
  local op=

  _parse_expr_factor
  local expr_node="$RV1"

  while _is_binop; do
    local t="$(peek 0)"
    local op="$(Token_get_val "$t")"
    incr_pos

    _parse_expr_factor
    node_r="$RV1"

    new_list
    expr_=$RV1

    List_add_str $expr_ "$op"
    List_add_node $expr_ $expr_node
    List_add_node $expr_ $node_r

    expr_node="list:${expr_}"
  done

  RV1="$expr_node"
}

parse_set() {
  consume "set"

  local t="$(peek 0)"
  incr_pos
  local var_name="$(Token_get_val "$t")"

  consume "="

  local expr_node=
  parse_expr
  expr_node="$RV1"

  consume ";"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "set"
  List_add_str $stmt_ "$var_name"
  List_add_node $stmt_ "$expr_node"

  RV1=$stmt_
}

_parse_arg() {
  local t="$(peek 0)"
  incr_pos

  local kind="$(Token_get_kind "$t")"
  local val="$(Token_get_val "$t")"

  case "$kind" in
    int          ) RV1="int:${val}"
  ;; str | ident ) RV1="str:${val}"
  ;; * )
       panic "_parse_arg: kind ($kind) t ($t)"
  esac
}

parse_args() {
  # puts_fn "parse_args"

  local t="$(peek 0)"
  local tv="$(Token_get_val "$t")"

  local args_=
  new_list
  args_=$RV1

  if [ "$tv" = ")" ]; then
    RV1=$args_
    return
  fi

  local arg_node=
  _parse_arg
  arg_node="$RV1"

  List_add_node $args_ "$arg_node"

  local t="$(peek 0)"
  local tv="$(Token_get_val "$t")"

  while [ "$tv" = "," ]; do
    consume ","

    _parse_arg
    arg_node="$RV1"

    List_add_node $args_ "$arg_node"

    local t="$(peek 0)"
    local tv="$(Token_get_val "$t")"
  done

  RV1=$args_
}

_parse_funcall() {
  local t="$(peek 0)"
  incr_pos
  local fn_name="$(Token_get_val "$t")"

  consume "("

  local args_=
  parse_args
  args_=$RV1

  consume ")"

  local funcall_=
  new_list
  funcall_=$RV1

  List_add_str $funcall_ "$fn_name"
  List_add_all $funcall_ $args_

  RV1=$funcall_
}

parse_call() {
  consume "call"

  local funcall_=
  _parse_funcall
  funcall_=$RV1

  consume ";"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "call"
  List_add_all $stmt_ $funcall_

  RV1=$stmt_
}

parse_call_set() {
  consume "call_set"

  local t="$(peek 0)"
  incr_pos
  local var_name="$(Token_get_val "$t")"

  consume "="

  local funcall_=
  _parse_funcall
  funcall_=$RV1

  consume ";"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "call_set"
  List_add_str $stmt_ "$var_name"
  List_add_list $stmt_ $funcall_

  RV1=$stmt_
}

parse_return() {
  consume "return"

  parse_expr
  local expr_node="$RV1"

  consume ";"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "return"
  List_add_node $stmt_ "$expr_node"

  RV1=$stmt_
}

parse_while() {
  puts_fn "parse_while"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "while"

  consume "while"
  consume "("

  parse_expr
  local expr_node="$RV1"
  List_add_node $stmt_ "$expr_node"

  consume ")"
  consume "{"

  parse_stmts
  local body_=$RV1

  List_add_list $stmt_ $body_

  consume "}"

  RV1=$stmt_
}

_parse_when_clause() {
  # puts_fn "_parse_when_clause"

  consume "when"
  consume "("

  parse_expr
  local expr_node="$RV1"

  consume ")"
  consume "{"

  parse_stmts
  local stmts_=$RV1

  consume "}"

  local when_clause_=
  new_list
  when_clause_=$RV1

  List_add_node $when_clause_ "$expr_node"
  List_add_all $when_clause_ $stmts_

  RV1=$when_clause_
}

parse_case() {
  puts_fn "parse_case"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "case"

  consume "case"

  local when_clause_=

  local t="$(peek 0)"
  local tv="$(Token_get_val "$t")"

  while [ "$tv" = "when" ]; do
    _parse_when_clause
    when_clause_="$RV1"
    List_add_list $stmt_ $when_clause_

    t="$(peek 0)"
    tv="$(Token_get_val "$t")"
  done

  RV1=$stmt_
}

parse_vm_comment() {
  consume "_cmt"
  consume "("

  local t="$(peek 0)"
  incr_pos
  local cmt="$(Token_get_val "$t")"

  consume ")"
  consume ";"

  new_list
  local stmt_=$RV1

  List_add_str $stmt_ "_cmt"
  List_add_str $stmt_ "$cmt"

  RV1=$stmt_
}

parse_debug() {
  consume "_debug"
  consume "("
  consume ")"
  consume ";"

  new_list
  local stmt_=$RV1

  List_add_str $stmt_ "_debug"

  RV1=$stmt_
}

parse_stmt() {
  local t="$(peek 0)"

  local head="$(Token_get_val "$t")"

  case "$head" in
    "set"       ) parse_set
  ;; "call"     ) parse_call
  ;; "call_set" ) parse_call_set
  ;; "return"   ) parse_return
  ;; "while"    ) parse_while
  ;; "case"     ) parse_case
  ;; "_cmt"     ) parse_vm_comment
  ;; "_debug"   ) parse_debug
  ;; * )
      panic "parse_stmt: unexpected token (${head})"
  esac
}

parse_stmts() {
  local stmts_=
  new_list
  stmts_=$RV1

  local stmt_=

  local t="$(peek 0)"
  local tv="$(Token_get_val "$t")"

  while [ "$tv" != "}" ]; do
    parse_stmt
    stmt_="$RV1"
    List_add_list $stmts_ $stmt_

    t="$(peek 0)"
    tv="$(Token_get_val "$t")"
  done

  RV1=$stmts_
}

_parse_var_declare() {
  # puts_fn "_parse_var_declare"

  local t="$(peek 0)"
  incr_pos

  local var_name="$(Token_get_val "$t")"

  consume ";"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "var"
  List_add_str $stmt_ "$var_name"

  RV1=$stmt_
}

_parse_var_init() {
  # puts_fn "_parse_var_init"

  local t="$(peek 0)"
  incr_pos

  local var_name="$(Token_get_val "$t")"

  consume "="

  local expr_node=
  parse_expr
  expr_node="$RV1"

  consume ";"

  local stmt_=
  new_list
  stmt_=$RV1

  List_add_str $stmt_ "var"
  List_add_str $stmt_ "$var_name"
  List_add_node $stmt_ "$expr_node"

  RV1=$stmt_
}

parse_var() {
  # puts_fn "parse_var"
  consume "var"

  local t="$(peek 1)"
  local t_val="$(Token_get_val "$t")"

  if [ "$t_val" = ";" ]; then
    _parse_var_declare
    #=> RV1
  elif [ "$t_val" = "=" ]; then
    _parse_var_init
    #=> RV1
  else
    panic "169"
  fi
}

parse_func_def() {
  puts_fn "parse_func_def"
  consume "func"

  local t="$(peek 0)"
  incr_pos

  local fn_name="$(Token_get_val "$t")"

  consume "("

  local fn_arg_names_=
  parse_args
  fn_arg_names_=$RV1

  consume ")"
  consume "{"

  local stmts_=
  new_list
  stmts_=$RV1

  t="$(peek 0)"
  local val="$(Token_get_val "$t")"
    
  while [ "$val" != "}" ]; do
    if [ "$val" = "var" ]; then
      parse_var
      stmt_=$RV1
      List_add_list $stmts_ $stmt_
    else
      parse_stmt
      stmt_=$RV1
      List_add_list $stmts_ $stmt_
    fi

    t="$(peek 0)"
    local val="$(Token_get_val "$t")"
  done

  consume "}"

  local func_=
  new_list
  func_=$RV1

  List_add_str $func_ "func"
  List_add_str $func_ "$fn_name"
  List_add_list $func_ $fn_arg_names_
  List_add_list $func_ $stmts_

  RV1=$func_
}

is_end() {
  if [ $ti -le $pos ]; then
    return $SH_OK
  else
    return $SH_NG
  fi
}

parse_top_stmt() {
  # puts_fn "parse_top_stmt"

  local t="$(peek 0)"
  local val="$(Token_get_val "$t")"

  if [ "$val" = "func" ]; then
    parse_func_def #=> RV1
  else
    panic "parse_top_stmt: unexpected token ($t) pos(${pos})"
  fi
}

parse_top_stmts() {
  local top_stmts_=
  new_list
  top_stmts_=$RV1

  List_add_str $top_stmts_ "top_stmts"

  local top_stmt_=
  while ! is_end; do
    parse_top_stmt
    top_stmt_=$RV1
    List_add_list $top_stmts_ $top_stmt_
  done

  RV1=$top_stmts_
}

parse() {
  read_tokens

  pos=0

  local top_stmts_=
  parse_top_stmts
  top_stmts_=$RV1

  json_print $top_stmts_
}

parse

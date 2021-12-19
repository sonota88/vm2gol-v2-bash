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

LABEL_ID=0

# --------------------------------

Names_index() {
  local self_="$1"; shift
  local target="$1"; shift

  local i=0
  local size=$(List_size $self_)
  while [ $i -lt $size ]; do
    local name="$(List_get_str $self_ $i)"
    if [ "$name" = "$target" ]; then
      echo $i
      return
    fi
    i=$((i + 1))
  done

  printf -- -1
}

Names_include() {
  local self_="$1"; shift
  local target="$1"; shift

  local i=$(Names_index $self_ "$target")
  if [ 0 -le $i ]; then
    return $SH_OK
  else
    return $SH_NG
  fi
}

fn_arg_disp() {
  local names_="$1"; shift
  local name="$1"; shift

  local i=$(Names_index $names_ "$name")
  local disp=$((i + 2))
  printf -- $disp
}

lvar_disp() {
  local names_="$1"; shift
  local name="$1"; shift

  local i=$(Names_index $names_ "$name")
  local disp=$(( 0 - (i + 1) ))
  printf -- $disp
}

get_label_id() {
  LABEL_ID=$((LABEL_ID + 1))
  RV1=$LABEL_ID
}

# --------------------------------

asm_prologue() {
  echo "  push bp"
  echo "  cp sp bp"
}

asm_epilogue() {
  echo "  cp bp sp"
  echo "  pop bp"
}

# --------------------------------

_gen_expr_add() {
  echo "  pop reg_b"
  echo "  pop reg_a"
  echo "  add_ab"
}

_gen_expr_mult() {
  echo "  pop reg_b"
  echo "  pop reg_a"
  echo "  mult_ab"
}

_gen_expr_eq() {
  get_label_id
  local label_id=$RV1

  local label_end="end_eq_${label_id}"
  local label_then="then_${label_id}"

  echo "  pop reg_b"
  echo "  pop reg_a"
  echo "  compare"
  echo "  jump_eq ${label_then}"
  echo "  cp 0 reg_a"
  echo "  jump ${label_end}"
  echo "label ${label_then}"
  echo "  cp 1 reg_a"
  echo "label ${label_end}"
}

_gen_expr_neq() {
  get_label_id
  local label_id=$RV1

  local label_end="end_neq_${label_id}"
  local label_then="then_${label_id}"

  echo "  pop reg_b"
  echo "  pop reg_a"
  echo "  compare"
  echo "  jump_eq ${label_then}"
  echo "  cp 1 reg_a"
  echo "  jump ${label_end}"
  echo "label ${label_then}"
  echo "  cp 0 reg_a"
  echo "label ${label_end}"
}

_gen_expr_binary() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local expr_="$1"; shift

  local op=$(List_get_str $expr_ 0)
  local node_l=$(List_get_node $expr_ 1)
  local node_r=$(List_get_node $expr_ 2)

  gen_expr $fn_arg_names_ $lvar_names_ "$node_l"
  echo "  push reg_a"
  gen_expr $fn_arg_names_ $lvar_names_ "$node_r"
  echo "  push reg_a"

  case "$op" in
    "+"   ) _gen_expr_add
  ;; "*"  ) _gen_expr_mult
  ;; "==" ) _gen_expr_eq
  ;; "!=" ) _gen_expr_neq
  ;; * )
       panic "_gen_expr_binary: unsupported op ($op)"
  esac
}

gen_expr() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local expr_node="$1"; shift

  Node_get "$expr_node"
  local type="$RV1"
  local val="$RV2"

  case "$type" in
    int )
      local n=$val
      echo "  cp ${n} reg_a"

  ;; str )
      local str="$val"

      if Names_include $lvar_names_ "$str"; then
        local disp=$(lvar_disp $lvar_names_ "$str")
        echo "  cp [bp:${disp}] reg_a"
      elif Names_include $fn_arg_names_ "$str"; then
        local disp=$(fn_arg_disp $fn_arg_names_ "$str")
        echo "  cp [bp:${disp}] reg_a"
      else
        panic "gen_expr: no such variable ($val)"
      fi

  ;; list )
      local list_=$val
      _gen_expr_binary $fn_arg_names_ $lvar_names_ $list_

  ;; * )
     panic "gen_expr: unsupported type (${type})"
  esac
}

_gen_set() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local var_name="$1"; shift
  local expr_node="$1"; shift

  gen_expr $fn_arg_names_ $lvar_names_ "$expr_node"

  if Names_include $lvar_names_ "$var_name"; then
    local disp=$(lvar_disp $lvar_names_ "$var_name")
    echo "  cp reg_a [bp:${disp}]"
  else
    panic "_gen_set: no such variable ($var_name)"
  fi
}

gen_set() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  local var_name=$(List_get_str $stmt_ 1)
  local expr_node=$(List_get_node $stmt_ 2)

  _gen_set $fn_arg_names_ $lvar_names_ "$var_name" "$expr_node"
}

_gen_funcall() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local funcall_="$1"; shift

  local fn_name="$(List_get_str $funcall_ 0)"
  local fn_args_=
  List_rest $funcall_
  fn_args_=$RV1

  local num_args=$(List_size $fn_args_)
  local arg=
  local i=$((num_args - 1))
  while [ 0 -le $i ]; do
    arg_node=$(List_get_node $fn_args_ $i)
    gen_expr $fn_arg_names_ $lvar_names_ "$arg_node"
    echo "  push reg_a"
    i=$((i - 1))
  done

  gen_vm_comment "call  ${fn_name}"

  echo "  call ${fn_name}"

  echo "  add_sp ${num_args}"
}

gen_call() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  local funcall_=
  List_rest $stmt_
  funcall_=$RV1

  _gen_funcall $fn_arg_names_ $lvar_names_ $funcall_
}

gen_call_set() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  local var_name=$(List_get_str $stmt_ 1)
  local funcall_=$(List_get_list $stmt_ 2)

  _gen_funcall $fn_arg_names_ $lvar_names_ $funcall_

  local disp=$(lvar_disp $lvar_names_ $var_name)
  echo "  cp reg_a [bp:${disp}]"
}

gen_return() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  local expr_node="$(List_get_node $stmt_ 1)"
  gen_expr $fn_arg_names_ $lvar_names_ "$expr_node"
}

gen_while() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  local expr_node="$(List_get_node $stmt_ 1)"
  local stmts_="$(List_get_list $stmt_ 2)"

  get_label_id
  local label_id=$RV1

  local label_beg="while_${label_id}"
  local label_end="end_while_${label_id}"

  echo "label ${label_beg}"

  gen_expr $fn_arg_names_ $lvar_names_ "$expr_node"

  echo "  cp 0 reg_b"
  echo "  compare"

  echo "  jump_eq ${label_end}"

  gen_stmts $fn_arg_names_ $lvar_names_ $stmts_

  echo "  jump ${label_beg}"
  echo "label ${label_end}"
}

gen_case() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  get_label_id
  local label_id=$RV1

  local label_end="end_case_${label_id}"
  local label_end_when_head="end_when_${label_id}"

  local when_clause_=
  local when_idx=-1

  local cond_node=
  local rest_=
  local size=$(List_size $stmt_)

  local i=1
  while [ $i -lt $size ]; do
    when_clause_=$(List_get_list $stmt_ $i)
    when_idx=$((when_idx + 1))
    
    cond_node="$(List_get_node $when_clause_ 0)"
    List_rest $when_clause_
    rest_=$RV1

    gen_expr $fn_arg_names_ $lvar_names_ "$cond_node"

    echo "  cp 0 reg_b"
    echo "  compare"
    echo "  jump_eq ${label_end_when_head}_${when_idx}"

    gen_stmts $fn_arg_names_ $lvar_names_ $rest_

    echo "  jump ${label_end}"
    echo "label ${label_end_when_head}_${when_idx}"

    i=$((i + 1))
  done

  echo "label ${label_end}"
}

gen_vm_comment() {
  local cmt="$1"; shift

  printf "  _cmt "
  printf "$cmt" | sed 's/ /~/g'
  printf "$LF"
}

gen_debug() {
  echo "  _debug"
}

gen_stmt() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  local head=$(List_get_str $stmt_ 0)
  case "$head" in
    "set"       ) gen_set      $fn_arg_names_ $lvar_names_ $stmt_
  ;; "call"     ) gen_call     $fn_arg_names_ $lvar_names_ $stmt_
  ;; "call_set" ) gen_call_set $fn_arg_names_ $lvar_names_ $stmt_
  ;; "return"   ) gen_return   $fn_arg_names_ $lvar_names_ $stmt_
  ;; "while"    ) gen_while    $fn_arg_names_ $lvar_names_ $stmt_
  ;; "case"     ) gen_case     $fn_arg_names_ $lvar_names_ $stmt_
  ;; "_cmt" )
       local cmt="$(List_get_str $stmt_ 1)"
       gen_vm_comment "$cmt"
  ;; "_debug"   ) gen_debug
  ;; * )
       panic "gen_stmt: unsupported sutmt ($head)"
  esac
}

gen_stmts() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmts_="$1"; shift

  local stmt_=
  local size=$(List_size $stmts_)

  local i=0
  while [ $i -lt $size ]; do
    stmt_=$(List_get_list $stmts_ $i)
    gen_stmt $fn_arg_names_ $lvar_names_ $stmt_
    i=$((i + 1))
  done
}

gen_var() {
  local fn_arg_names_="$1"; shift
  local lvar_names_="$1"; shift
  local stmt_="$1"; shift

  echo "  sub_sp 1"

  local size=$(List_size $stmt_)
  if [ $size -eq 3 ]; then
    local dest="$(List_get_str $stmt_ 1)"
    local expr_node="$(List_get_node $stmt_ 2)"
    _gen_set $fn_arg_names_ $lvar_names_ "$dest" "$expr_node"
  fi
}

gen_func_def() {
  puts_fn "gen_func_def"

  local fn_name="$(List_get_str $top_stmt_ 1)"
  local fn_arg_names_="$(List_get_list $top_stmt_ 2)"
  local stmts_="$(List_get_list $top_stmt_ 3)"

  echo "label ${fn_name}"
  asm_prologue

  local lvar_names_=
  new_list
  lvar_names_=$RV1

  local i=0
  local size=$(List_size stmts_)
  local stmt_=
  local stmt_head=

  while [ $i -lt $size ]; do
    stmt_=$(List_get_list $stmts_ $i)

    stmt_head="$(List_get_str $stmt_ 0)"
    if [ "$stmt_head" = "var" ]; then
      local var_name="$(List_get_str $stmt_ 1)"
      List_add_str $lvar_names_ "$var_name"
      gen_var $fn_arg_names_ $lvar_names_ $stmt_
    else
      gen_stmt $fn_arg_names_ $lvar_names_ $stmt_
    fi

    i=$((i + 1))
  done

  asm_epilogue
  echo "  ret"
}

gen_top_stmt() {
  local top_stmt_="$1"; shift

  local node0="$(List_get_node $top_stmt_ 0)"
  local node0v="$(Node_get_val "$node0")"

  if [ "$node0v" = "func" ]; then
    gen_func_def $top_stmt_
  else
    panic "unsupported top stmt (${node0v})"
  fi
}

gen_top_stmts() {
  local ast_="$1"; shift

  local size=$(List_size $ast_)
  # echo_kv_e size $size
  local i=1
  local node=

  while [ $i -lt $size ]; do
    node=$(List_get_node $ast_ $i)
    top_stmt_=$(Node_get_val "$node")
    gen_top_stmt $top_stmt_
    i=$((i + 1))
  done
}

gen_builtin_set_vram() {
  echo "label set_vram"
  asm_prologue
  echo "  set_vram [bp:2] [bp:3]"
  asm_epilogue
  echo "  ret"
}

gen_builtin_get_vram() {
  echo "label get_vram"
  asm_prologue
  echo "  get_vram [bp:2] reg_a"
  asm_epilogue
  echo "  ret"
}

codegen() {
  read_stdin_all
  local json="$RV1"

  local ast_=

  json_parse "$json"
  ast_=$RV1

  echo "  call main"
  echo "  exit"

  gen_top_stmts $ast_

  echo "#>builtins"
  gen_builtin_set_vram
  gen_builtin_get_vram
  echo "#<builtins"
}

codegen

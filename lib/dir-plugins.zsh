# dir-plugins: enable extra plugins per directory.
#
# Keeps the set of loaded "directory plugins" in sync with the
# $OMZ_DIR_PLUGINS environment variable, a space-separated list of plugin
# names. Anything may set the variable; the expected producer is direnv via
# a project .envrc:
#
#   export OMZ_DIR_PLUGINS="docker kubectl"
#
# Plugins load when the variable gains their name and unload when it loses
# it. Unloading reverses what the plugin defined while it was sourced.
# Exported environment variables, setopt changes, and background processes
# are not reverted; a plugin may define `<name>_plugin_unload` to clean
# those up itself.

typeset -gA _omz_dirplug_logs      # plugin name -> undo log
typeset -ga _omz_dirplug_loaded    # loaded dir plugins, in load order
typeset -g  _omz_dirplug_last=''   # last-seen value of $OMZ_DIR_PLUGINS
typeset -ga _omz_dirplug_rec       # undo records of the plugin being loaded
typeset -gA _omz_dirplug_prev_fn        # shadowed function bodies to restore
typeset -ga _omz_dirplug_shadow_names
_omz_dirplug_shadow_names=(alias unalias autoload bindkey zle zstyle compdef)

# Undo log format: records joined with \x1e, fields within a record joined
# with \x1f. Field 1 is the record type.

# No `emulate -L zsh` here: LOCAL_OPTIONS is dynamically scoped, and this
# function calls _omz_dirplug_load, which sources plugin code further down
# the call chain. Localizing options here would revert any setopt a plugin
# makes as soon as sync returns.
_omz_dirplug_sync() {
  [[ "${OMZ_DIR_PLUGINS-}" == "$_omz_dirplug_last" ]] && return 0
  _omz_dirplug_last="${OMZ_DIR_PLUGINS-}"

  local -a to_load to_unload
  () {
    emulate -L zsh
    local -aU want
    want=(${=OMZ_DIR_PLUGINS-})
    want=(${want:|plugins})   # user-level plugins are not ours to manage
    to_unload=(${(Oa)${_omz_dirplug_loaded:|want}})   # reverse load order
    to_load=(${want:|_omz_dirplug_loaded})
  }

  local name
  for name in "${to_unload[@]}"; do
    _omz_dirplug_unload "$name"
  done
  for name in "${to_load[@]}"; do
    _omz_dirplug_load "$name"
  done
}

_omz_dirplug_shadow_on() {
  emulate -L zsh
  local name wrap
  for name in $_omz_dirplug_shadow_names; do
    wrap="${name//-/_}"
    if (( ${+functions[$name]} )); then
      _omz_dirplug_prev_fn[$name]="$functions[$name]"
      functions[_omz_dirplug_real_$wrap]="$functions[$name]"
    fi
    functions[$name]="$functions[_omz_dirplug_wrap_$wrap]"
  done
}

_omz_dirplug_shadow_off() {
  emulate -L zsh
  local name wrap
  for name in $_omz_dirplug_shadow_names; do
    wrap="${name//-/_}"
    if (( ${+_omz_dirplug_prev_fn[$name]} )); then
      functions[$name]="$_omz_dirplug_prev_fn[$name]"
    else
      unfunction -- "$name" 2>/dev/null
    fi
    unfunction -- "_omz_dirplug_real_$wrap" 2>/dev/null
  done
  _omz_dirplug_prev_fn=()
}

_omz_dirplug_wrap_alias() {
  emulate -L zsh
  local arg name kind=a
  for arg in "$@"; do
    case "$arg" in
    -g) kind=g ;;
    -s) kind=s ;;
    -*) ;;
    *=*)
      name="${arg%%=*}"
      case "$kind" in
      a)
        if (( ${+aliases[$name]} )); then
          _omz_dirplug_rec+=("alias_overwrote"$'\x1f'"$name"$'\x1f'"${aliases[$name]}")
        else
          _omz_dirplug_rec+=("alias_new"$'\x1f'"$name")
        fi
        ;;
      g)
        if (( ${+galiases[$name]} )); then
          _omz_dirplug_rec+=("galias_overwrote"$'\x1f'"$name"$'\x1f'"${galiases[$name]}")
        else
          _omz_dirplug_rec+=("galias_new"$'\x1f'"$name")
        fi
        ;;
      esac
      ;;
    esac
  done
  builtin alias "$@"
}

_omz_dirplug_wrap_unalias() {
  emulate -L zsh
  local arg
  for arg in "$@"; do
    [[ "$arg" == -* ]] && continue
    if (( ${+aliases[$arg]} )); then
      _omz_dirplug_rec+=("alias_removed"$'\x1f'"$arg"$'\x1f'"${aliases[$arg]}"$'\x1f'"a")
    elif (( ${+galiases[$arg]} )); then
      _omz_dirplug_rec+=("alias_removed"$'\x1f'"$arg"$'\x1f'"${galiases[$arg]}"$'\x1f'"g")
    fi
  done
  builtin unalias "$@"
}

# Redundant with the functions-table diff in _omz_dirplug_load for most
# calls, but catches names an interrupted source would otherwise miss.
# Duplicate records are harmless: unload guards on existence.
_omz_dirplug_wrap_autoload() {
  emulate -L zsh
  local arg
  for arg in "$@"; do
    [[ "$arg" == [-+]* ]] && continue
    (( ${+functions[$arg]} )) && continue
    _omz_dirplug_rec+=("function_new"$'\x1f'"$arg")
  done
  builtin autoload "$@"
}

# Tracks the forms `bindkey [-M keymap] [-s] in-string out`. Other forms
# (keymap creation, -e/-v, listing) are forwarded untracked.
_omz_dirplug_wrap_bindkey() {
  emulate -L zsh
  local km=main
  local -a args
  args=("$@")
  if [[ "${args[1]-}" == -M ]]; then
    km="${args[2]-}"
    args=("${(@)args[3,-1]}")
  fi
  if [[ "${args[1]-}" == -s ]]; then
    args=("${(@)args[2,-1]}")
  fi
  if [[ $#args -eq 2 && "${args[1]}" != -* ]]; then
    local seq="${args[1]}" prev prevkind=none prevvalue=''
    prev="$(builtin bindkey -M "$km" -- "$seq" 2>/dev/null)"
    prev="${prev#*\" }"
    if [[ -z "$prev" || "$prev" == undefined-key ]]; then
      prevkind=none
    elif [[ "$prev" == \"*\" ]]; then
      prevkind=string
      prevvalue="${${prev#\"}%\"}"
    else
      prevkind=widget
      prevvalue="$prev"
    fi
    _omz_dirplug_rec+=("bindkey"$'\x1f'"$km"$'\x1f'"$seq"$'\x1f'"$prevkind"$'\x1f'"$prevvalue")
  fi
  builtin bindkey "$@"
}

_omz_dirplug_wrap_zle() {
  emulate -L zsh
  if [[ "${1-}" == -N && -n "${2-}" ]]; then
    if (( ${+widgets[$2]} )); then
      _omz_dirplug_rec+=("widget_overwrote"$'\x1f'"$2"$'\x1f'"${widgets[$2]}")
    else
      _omz_dirplug_rec+=("widget_new"$'\x1f'"$2")
    fi
  fi
  builtin zle "$@"
}

# Tracks the setting forms `zstyle pattern style ...` and
# `zstyle -e pattern style ...`. Queries and deletions are forwarded
# untracked. Restoring an overwritten -e style loses its eval flag.
_omz_dirplug_wrap_zstyle() {
  emulate -L zsh
  local pat style
  if [[ $# -ge 2 && "${1-}" != -* ]]; then
    pat="$1" style="$2"
  elif [[ "${1-}" == -e && $# -ge 3 ]]; then
    pat="$2" style="$3"
  fi
  if [[ -n "$pat" ]]; then
    local -a prev
    if builtin zstyle -g prev "$pat" "$style" && (( $#prev )); then
      _omz_dirplug_rec+=("zstyle_overwrote"$'\x1f'"$pat"$'\x1f'"$style"$'\x1f'"${(pj:\x1f:)prev}")
    else
      _omz_dirplug_rec+=("zstyle_new"$'\x1f'"$pat"$'\x1f'"$style")
    fi
  fi
  builtin zstyle "$@"
}

# compdef is a function defined by compinit, so the original is forwarded
# to via the copy _omz_dirplug_shadow_on made. The _comps diff catches
# every command the call affected, whatever its argument form.
_omz_dirplug_wrap_compdef() {
  emulate -L zsh
  local -A comps_pre
  comps_pre=("${(@kv)_comps}")
  if (( ${+functions[_omz_dirplug_real_compdef]} )); then
    _omz_dirplug_real_compdef "$@"
  fi
  local cmd
  for cmd in ${(k)_comps}; do
    if (( ! ${+comps_pre[$cmd]} )); then
      _omz_dirplug_rec+=("comp_new"$'\x1f'"$cmd")
    elif [[ "${_comps[$cmd]}" != "${comps_pre[$cmd]}" ]]; then
      _omz_dirplug_rec+=("comp_overwrote"$'\x1f'"$cmd"$'\x1f'"${comps_pre[$cmd]}")
    fi
  done
}

# compinit already ran at startup, so completion files of a directory
# plugin are not picked up from fpath. Register them directly: parse each
# _file's `#compdef cmd...` line, mark the function for autoload, and map
# the commands in _comps.
_omz_dirplug_register_completions() {
  emulate -L zsh
  local base="$1" cfile fun line cmd
  (( ${+_comps} )) || return 0
  for cfile in "$base"/_*(N.); do
    fun="${cfile:t}"
    read -r line < "$cfile" || continue
    [[ "$line" == '#compdef '* ]] || continue
    (( ${+functions[$fun]} )) && continue
    builtin autoload -Uz "$fun"
    _omz_dirplug_rec+=("function_new"$'\x1f'"$fun")
    for cmd in ${${=line}[2,-1]}; do
      [[ "$cmd" == -* ]] && continue
      if (( ${+_comps[$cmd]} )); then
        _omz_dirplug_rec+=("comp_overwrote"$'\x1f'"$cmd"$'\x1f'"${_comps[$cmd]}")
      else
        _omz_dirplug_rec+=("comp_new"$'\x1f'"$cmd")
      fi
      _comps[$cmd]="$fun"
    done
  done
}

# No `emulate -L zsh` on this function itself, and note the `source` line
# below is not inside any of the anonymous functions either: the plugin
# must be sourced under the same shell options a startup plugin gets, and
# any setopt it performs must persist. All the surrounding bookkeeping runs
# inside `emulate -L zsh` anonymous functions instead, so ambient options
# (e.g. KSH_ARRAYS) can't corrupt the before/after diff, while `emulate -L`
# reverts when each anonymous function returns and never leaks into the
# source line or the caller.
_omz_dirplug_load() {
  local name="$1" base
  if is_plugin "$ZSH_CUSTOM" "$name"; then
    base="$ZSH_CUSTOM/plugins/$name"
  elif is_plugin "$ZSH" "$name"; then
    base="$ZSH/plugins/$name"
  else
    print -ru2 -- "[oh-my-zsh] dir plugin '$name' not found"
    return 1
  fi

  local -a fpath_pre fkeys_pre
  () {
    emulate -L zsh
    fpath_pre=($fpath)
    fkeys_pre=(${(k)functions})
  }
  fpath=("$base" "${fpath[@]}")
  _omz_dirplug_rec=()

  _omz_dirplug_shadow_on
  {
    if [[ -f "$base/$name.plugin.zsh" ]]; then
      builtin source "$base/$name.plugin.zsh"
    fi
  } always {
    _omz_dirplug_shadow_off
  }

  () {
    emulate -L zsh
    local f d
    for f in ${${(k)functions}:|fkeys_pre}; do
      [[ "$f" == _omz_dirplug* ]] && continue
      _omz_dirplug_rec+=("function_new"$'\x1f'"$f")
    done
    for d in ${fpath:|fpath_pre}; do
      _omz_dirplug_rec+=("fpath_add"$'\x1f'"$d")
    done
    _omz_dirplug_register_completions "$base"
    _omz_dirplug_logs[$name]="${(pj:\x1e:)_omz_dirplug_rec}"
  }
  _omz_dirplug_loaded+=("$name")
}

_omz_dirplug_unload() {
  emulate -L zsh
  local name="$1" rec
  local -a records fields wparts

  records=("${(@ps:\x1e:)_omz_dirplug_logs[$name]}")
  for rec in ${(Oa)records}; do
    fields=("${(@ps:\x1f:)rec}")
    case "${fields[1]}" in
    function_new)
      (( ${+functions[${fields[2]}]} )) && unfunction -- "${fields[2]}"
      ;;
    fpath_add)
      fpath=(${fpath:#${fields[2]}})
      ;;
    alias_new)
      builtin unset "aliases[${fields[2]}]" 2>/dev/null
      ;;
    alias_overwrote)
      aliases[${fields[2]}]="${fields[3]}"
      ;;
    galias_new)
      builtin unset "galiases[${fields[2]}]" 2>/dev/null
      ;;
    galias_overwrote)
      galiases[${fields[2]}]="${fields[3]}"
      ;;
    alias_removed)
      case "${fields[4]}" in
      a) aliases[${fields[2]}]="${fields[3]}" ;;
      g) galiases[${fields[2]}]="${fields[3]}" ;;
      esac
      ;;
    bindkey)
      case "${fields[4]}" in
      none)   builtin bindkey -M "${fields[2]}" -r -- "${fields[3]}" 2>/dev/null ;;
      widget) builtin bindkey -M "${fields[2]}" -- "${fields[3]}" "${fields[5]}" ;;
      string) builtin bindkey -M "${fields[2]}" -s -- "${fields[3]}" "${fields[5]}" ;;
      esac
      ;;
    widget_new)
      builtin zle -D "${fields[2]}" 2>/dev/null
      ;;
    widget_overwrote)
      case "${fields[3]}" in
      user:*)
        builtin zle -N "${fields[2]}" "${fields[3]#user:}"
        ;;
      completion:*)
        wparts=(${(s.:.)fields[3]})
        builtin zle -C "${fields[2]}" "${wparts[2]}" "${wparts[3]}"
        ;;
      builtin)
        builtin zle -A ".${fields[2]}" "${fields[2]}"
        ;;
      esac
      ;;
    zstyle_new)
      builtin zstyle -d "${fields[2]}" "${fields[3]}"
      ;;
    zstyle_overwrote)
      builtin zstyle "${fields[2]}" "${fields[3]}" "${(@)fields[4,-1]}"
      ;;
    comp_new)
      builtin unset "_comps[${fields[2]}]" 2>/dev/null
      ;;
    comp_overwrote)
      _comps[${fields[2]}]="${fields[3]}"
      ;;
    esac
  done

  builtin unset "_omz_dirplug_logs[$name]"
  _omz_dirplug_loaded=(${_omz_dirplug_loaded:#$name})
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _omz_dirplug_sync

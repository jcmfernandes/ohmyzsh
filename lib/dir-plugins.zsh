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

# Undo log format: records joined with \x1e, fields within a record joined
# with \x1f. Field 1 is the record type.

# No `emulate -L zsh` here: LOCAL_OPTIONS is dynamically scoped, and this
# function calls _omz_dirplug_load, which sources plugin code further down
# the call chain. Localizing options here would revert any setopt a plugin
# makes as soon as sync returns.
_omz_dirplug_sync() {
  [[ "${OMZ_DIR_PLUGINS-}" == "$_omz_dirplug_last" ]] && return 0
  _omz_dirplug_last="${OMZ_DIR_PLUGINS-}"

  local -aU want
  local -a to_load to_unload
  want=(${=OMZ_DIR_PLUGINS-})
  want=(${want:|plugins})   # user-level plugins are not ours to manage
  to_unload=(${_omz_dirplug_loaded:|want})
  to_load=(${want:|_omz_dirplug_loaded})

  local name
  for name in ${(Oa)to_unload}; do   # unload in reverse load order
    _omz_dirplug_unload "$name"
  done
  for name in $to_load; do
    _omz_dirplug_load "$name"
  done
}

# No `emulate -L zsh` here: the plugin must be sourced under the same shell
# options a startup plugin gets, and any setopt it performs must persist.
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
  fpath_pre=($fpath)
  fkeys_pre=(${(k)functions})
  fpath=("$base" $fpath)
  _omz_dirplug_rec=()

  if [[ -f "$base/$name.plugin.zsh" ]]; then
    builtin source "$base/$name.plugin.zsh"
  fi

  local f
  for f in ${${(k)functions}:|fkeys_pre}; do
    [[ "$f" == _omz_dirplug* ]] && continue
    _omz_dirplug_rec+=("function_new"$'\x1f'"$f")
  done
  local d
  for d in ${fpath:|fpath_pre}; do
    _omz_dirplug_rec+=("fpath_add"$'\x1f'"$d")
  done

  _omz_dirplug_logs[$name]="${(pj:\x1e:)_omz_dirplug_rec}"
  _omz_dirplug_loaded+=("$name")
}

_omz_dirplug_unload() {
  emulate -L zsh
  local name="$1" rec
  local -a records fields

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
    esac
  done

  builtin unset "_omz_dirplug_logs[$name]"
  _omz_dirplug_loaded=(${_omz_dirplug_loaded:#$name})
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _omz_dirplug_sync

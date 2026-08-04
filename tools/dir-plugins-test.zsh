#!/usr/bin/env zsh
# Standalone tests for lib/dir-plugins.zsh.
# Usage: zsh -f tools/dir-plugins-test.zsh
# No direnv required: tests set/unset OMZ_DIR_PLUGINS and call the sync
# hook directly.

TESTDIR="${0:a:h}/dir-plugins-test"
export ZSH="${0:a:h:h}"
ZSH_CUSTOM="$TESTDIR/fixtures"
ZSH_CACHE_DIR="$(mktemp -d)"
ZSH_COMPDUMP="$ZSH_CACHE_DIR/zcompdump"
ZSH_THEME=""
ZSH_DISABLE_COMPFIX=true
trap 'rm -rf "$ZSH_CACHE_DIR"' EXIT

zmodload -i zsh/zle
zstyle ':omz:update' mode disabled

plugins=(git)
source "$ZSH/oh-my-zsh.sh"

typeset -gi T_PASS=0 T_FAIL=0
t_assert() {
  if eval "$2"; then
    (( ++T_PASS )); print -r -- "ok - $1"
  else
    (( ++T_FAIL )); print -r -- "FAIL - $1"
  fi
}

# --- load/unload basics ------------------------------------------------------
OMZ_DIR_PLUGINS="basicplug"
_omz_dirplug_sync
t_assert "load: plugin function defined" \
  '(( ${+functions[basicplug_hello]} ))'
t_assert "load: autoloaded function marked" \
  '(( ${+functions[basicplug_auto]} ))'
t_assert "load: plugin dir in fpath" \
  '(( ${fpath[(Ie)$ZSH_CUSTOM/plugins/basicplug]} ))'
t_assert "load: plugin recorded as loaded" \
  '(( ${_omz_dirplug_loaded[(Ie)basicplug]} ))'

unset OMZ_DIR_PLUGINS
_omz_dirplug_sync
t_assert "unload: plugin function removed" \
  '(( ! ${+functions[basicplug_hello]} ))'
t_assert "unload: autoloaded function removed" \
  '(( ! ${+functions[basicplug_auto]} ))'
t_assert "unload: plugin dir removed from fpath" \
  '(( ! ${fpath[(Ie)$ZSH_CUSTOM/plugins/basicplug]} ))'
t_assert "unload: loaded list empty" \
  '(( $#_omz_dirplug_loaded == 0 ))'

# --- user-level plugins are skipped ------------------------------------------
OMZ_DIR_PLUGINS="git basicplug"
_omz_dirplug_sync
t_assert "skip: user-level plugin not managed" \
  '(( ! ${_omz_dirplug_loaded[(Ie)git]} ))'
unset OMZ_DIR_PLUGINS
_omz_dirplug_sync
t_assert "skip: user-level plugin untouched by unload" \
  '(( ${+aliases[gst]} ))'

# --- unknown plugin warns once, others still load ----------------------------
OMZ_DIR_PLUGINS="nosuchplugin basicplug"
_omz_dirplug_sync 2> "$ZSH_CACHE_DIR/warn1.txt"
t_assert "unknown: warning printed" \
  'grep -q nosuchplugin "$ZSH_CACHE_DIR/warn1.txt"'
t_assert "unknown: other plugin still loaded" \
  '(( ${+functions[basicplug_hello]} ))'
_omz_dirplug_sync 2> "$ZSH_CACHE_DIR/warn2.txt"
t_assert "unknown: no re-warn while value unchanged" \
  '[[ ! -s "$ZSH_CACHE_DIR/warn2.txt" ]]'
unset OMZ_DIR_PLUGINS
_omz_dirplug_sync

# --- delta sync --------------------------------------------------------------
OMZ_DIR_PLUGINS="basicplug otherplug"
_omz_dirplug_sync
OMZ_DIR_PLUGINS="otherplug"
_omz_dirplug_sync
t_assert "delta: removed plugin unloaded" \
  '(( ! ${+functions[basicplug_hello]} ))'
t_assert "delta: kept plugin untouched" \
  '(( ${+functions[otherplug_hello]} ))'
unset OMZ_DIR_PLUGINS
_omz_dirplug_sync

# --- plugin setopt persistence -----------------------------------------------
unsetopt pushd_ignore_dups 2>/dev/null
OMZ_DIR_PLUGINS="optplug"
_omz_dirplug_sync
t_assert "options: plugin setopt persists after load" \
  '[[ -o pushd_ignore_dups ]]'
unset OMZ_DIR_PLUGINS
_omz_dirplug_sync
t_assert "options: setopt not reverted by unload" \
  '[[ -o pushd_ignore_dups ]]'
unsetopt pushd_ignore_dups

# --- sync robust under ksh_arrays --------------------------------------------
setopt ksh_arrays
OMZ_DIR_PLUGINS="basicplug otherplug"
_omz_dirplug_sync
unsetopt ksh_arrays
t_assert "ksh_arrays: both plugins loaded" \
  '(( ${+functions[basicplug_hello]} )) && (( ${+functions[otherplug_hello]} ))'
setopt ksh_arrays
OMZ_DIR_PLUGINS="otherplug"
_omz_dirplug_sync
unsetopt ksh_arrays
t_assert "ksh_arrays: delta unload correct" \
  '(( ! ${+functions[basicplug_hello]} )) && (( ${+functions[otherplug_hello]} ))'
unset OMZ_DIR_PLUGINS
_omz_dirplug_sync

# --- alias tracking and restore ----------------------------------------------
alias ovr_alias='echo original'
alias ovr_removed='echo original-removed'
OMZ_DIR_PLUGINS="overwriteplug"
_omz_dirplug_sync
t_assert "alias: plugin overwrote alias" \
  '[[ ${aliases[ovr_alias]} == "echo plugin-version" ]]'
t_assert "alias: plugin removed alias" \
  '(( ! ${+aliases[ovr_removed]} ))'
t_assert "alias: global alias defined" \
  '(( ${+galiases[OVRG]} ))'
t_assert "shadow: wrappers not active outside sourcing" \
  '(( ! ${+functions[alias]} ))'

unset OMZ_DIR_PLUGINS
_omz_dirplug_sync
t_assert "restore: overwritten alias restored" \
  '[[ ${aliases[ovr_alias]} == "echo original" ]]'
t_assert "restore: new alias removed" \
  '(( ! ${+aliases[ovr_new]} ))'
t_assert "restore: new global alias removed" \
  '(( ! ${+galiases[OVRG]} ))'
t_assert "restore: removed alias restored" \
  '[[ ${aliases[ovr_removed]} == "echo original-removed" ]]'
unalias ovr_alias ovr_removed

# --- results -----------------------------------------------------------------
print -r -- "# pass: $T_PASS fail: $T_FAIL"
(( T_FAIL == 0 ))

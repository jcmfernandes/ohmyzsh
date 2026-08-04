hookplug_precmd() { typeset -g HOOKPLUG_PRECMD_RAN=1 }
add-zsh-hook precmd hookplug_precmd
hookplug_plugin_unload() {
  typeset -ga UNLOAD_ORDER
  UNLOAD_ORDER+=("hookplug")
}

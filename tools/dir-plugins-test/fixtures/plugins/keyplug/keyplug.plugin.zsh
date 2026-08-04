keyplug_widget() { zle -M keyplug }
zle -N keyplug-widget keyplug_widget
zle -N up-line-or-history keyplug_widget
bindkey '^Xz' keyplug-widget
bindkey '^Xq' keyplug-widget

# Mirrors the aws plugin: define a prompt helper, then splice a call to it
# into the prompt. Unload must undo both or the prompt calls a dead function.
promptplug_info() { print -n "PP" }
RPROMPT='$(promptplug_info)'"$RPROMPT"
PROMPT="[pp]$PROMPT"

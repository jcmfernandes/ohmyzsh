if (( ! $+commands[mise] )); then
  return
fi

# Load mise hooks
eval "$(mise activate zsh)"

# If the completion file doesn't exist yet, we need to autoload it and
# bind it to `mise`. Otherwise, compinit will have already done that.
local comp_file="$ZSH_CACHE_DIR/completions/_mise"

if [[ ! -f "$comp_file" ]]; then
  typeset -g -A _comps
  autoload -Uz _mise
  _comps[mise]=_mise
fi

# Generate and load mise completion, only when missing/empty or stale. stderr
# is redirected because mise prompts on it when it's a tty (e.g. to trust a
# config file); as a tty's fd 2 is read-write, that prompt reads from the
# terminal too, raising SIGTTIN and stopping this background job mid-prompt --
# after it has emitted "hide cursor" but never the restore, leaving the
# terminal without a visible cursor.
if [[ ! -s "$comp_file" || "$commands[mise]" -nt "$comp_file" ]]; then
  mise completion zsh >| "$comp_file" 2>/dev/null &|
fi

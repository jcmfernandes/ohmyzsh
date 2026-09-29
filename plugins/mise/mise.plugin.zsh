if (( $+commands[mise] )); then
  _mise_bin=mise
elif [[ -x ~/.local/bin/mise ]]; then
  _mise_bin=~/.local/bin/mise
else
  return
fi

# Load mise hooks
eval "$($_mise_bin activate zsh)"
unset _mise_bin

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
  zmodload -F zsh/files b:zf_mv
  () {
    # TMPPREFIX puts the process substitution's temporary file next to the
    # cache file, so zf_mv installs it with a rename and no shell ever reads
    # a half-written completion. The leading dot keeps it out of compinit's
    # $fpath scan.
    local TMPPREFIX="$ZSH_CACHE_DIR/completions/._mise"
    zf_mv -f -- =( mise completion zsh 2>/dev/null ) "$comp_file"
  } &|
fi

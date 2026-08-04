alias dbl='docker build'
alias dcin='docker container inspect'
alias dcls='docker container ls'
alias dclsa='docker container ls -a'
alias dcprune='docker container prune'
alias dib='docker image build'
alias dii='docker image inspect'
alias dils='docker image ls'
alias dipu='docker image push'
alias dipru='docker image prune -a'
alias dirm='docker image rm'
alias dit='docker image tag'
alias dlo='docker container logs'
alias dnc='docker network create'
alias dncn='docker network connect'
alias dndcn='docker network disconnect'
alias dni='docker network inspect'
alias dnls='docker network ls'
alias dnprune='docker network prune'
alias dnrm='docker network rm'
alias dpo='docker container port'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias dpu='docker pull'
alias dr='docker container run'
alias drit='docker container run -it'
alias drm='docker container rm'
alias 'drm!'='docker container rm -f'
alias dsprune='docker system prune'
alias dst='docker container start'
alias drs='docker container restart'
alias dsta='docker stop $(docker ps -q)'
alias dstp='docker container stop'
alias dsts='docker stats'
alias dtop='docker top'
alias dvi='docker volume inspect'
alias dvls='docker volume ls'
alias dvprune='docker volume prune'
alias dxc='docker container exec'
alias dxcit='docker container exec -it'

if (( ! $+commands[docker] )); then
  return
fi

# Standardized $0 handling
# https://zdharma-continuum.github.io/Zsh-100-Commits-Club/Zsh-Plugin-Standard.html
0="${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}"
0="${${(M)0:#/*}:-$PWD/$0}"

# If the completion file doesn't exist yet, we need to autoload it and
# bind it to `docker`. Otherwise, compinit will have already done that.
if [[ ! -f "$ZSH_CACHE_DIR/completions/_docker" ]]; then
  typeset -g -A _comps
  autoload -Uz _docker
  _comps[docker]=_docker
fi

{
  # `docker completion` exists in Docker 23.0.0 and later, and in every
  # Docker-compatible CLI built with cobra (Podman's docker wrapper, nerdctl,
  # ...). Those wrappers report their own version -- Podman prints
  # `docker version 5.8.2` -- so comparing `docker --version` against 23.0.0
  # misreads them as legacy and hands them Docker's bundled completion, which
  # doesn't describe the CLI they actually run. Ask the CLI to generate one,
  # and only fall back to the bundled file when it can't.
  if ! zstyle -t ':omz:plugins:docker' legacy-completion && \
    _docker_completion="$(command docker completion zsh 2>/dev/null)" && \
    [[ -n "$_docker_completion" ]]; then
        # The cached file may be an unwritable copy of the bundled one (see
        # below), so replace it instead of truncating it in place.
        command rm -f "$ZSH_CACHE_DIR/completions/_docker"
        print -r -- "$_docker_completion" > "$ZSH_CACHE_DIR/completions/_docker"
      else
        # -f: the bundled file can sit on read-only media -- a Nix store path,
        # say -- and cp copies its mode, leaving behind a destination that no
        # later run can open for writing.
        command cp -f "${0:h}/completions/_docker" "$ZSH_CACHE_DIR/completions/_docker"
  fi
} &|

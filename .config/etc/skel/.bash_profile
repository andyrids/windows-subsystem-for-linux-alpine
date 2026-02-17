# .bash_profile

# load .profile settings
[ -f $HOME/.profile ] && source $HOME/.profile

# https://github.com/fastfetch-cli/fastfetch
fastfetch

# Get the aliases and functions
[ -f $HOME/.bashrc ] && source $HOME/.bashrc

# source any custom environment variables if this file exists
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"
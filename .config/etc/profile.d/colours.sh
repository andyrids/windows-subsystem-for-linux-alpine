# /etc/profile.d/colours.sh

# Colour support for non-bash shells (BusyBox ash, etc.)
# Bash handles its own colours in `~/.bashrc`, which supports
# \[...\] non-printing wrappers that ash does not understand.

# Skip entirely when running under bash
[ -n "$BASH_VERSION" ] && return 2>/dev/null

# Enable colour support for the terminal
case "$TERM" in
    xterm-color|*-256color)
        color_prompt=yes
        ;;
esac

# Set colour prompt with raw \033 escapes (ash/sh)
if [ "$color_prompt" = yes ]; then
    PS1='\033[01;32m\u@\h\033[00m:\033[01;34m\w\033[00m\$ '
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
else
    PS1='\u@\h:\w\$ '
fi
unset color_prompt
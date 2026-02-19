# .bashrc

# if not running interactively, don't do anything
[[ $- != *i* ]] && return

# Do not put duplicate lines or lines starting with space in the history
HISTCONTROL=ignoreboth

# Append to the history file
shopt -s histappend

# For setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=1000
HISTFILESIZE=2000

# Check window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# Enable colour support for the terminal
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# Set colour prompt (\[...\] wrappers for bash)
if [ "$color_prompt" = yes ]; then
    PS1='\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='[\u@\h \W]\$ '
fi
unset color_prompt

# Set terminal title (if using xterm)
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# Colour aliases for BusyBox applets
alias ls='ls --color=auto'
alias grep='grep --color=auto'

# Common aliases for ls
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Load environment variables
if [ -f "$HOME/.local/bin/env" ]; then
    . "$HOME/.local/bin/env"
fi
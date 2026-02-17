# /etc/profile.d/colors.sh

# enable color support for the terminal
case "$TERM" in
    xterm-color|*-256color|xterm-256color) 
        color_prompt=yes
        ;;
esac

# set coloured prompt
if [ "$color_prompt" = yes ]; then
    # Alpine/Ash prompt with colors: Green for user@host, Blue for path
    PS1='\033[01;32m\u@\h\033[00m:\033[01;34m\w\033[00m\$ '
else
    PS1='\u@\h:\w\$ '
fi
unset color_prompt

# colour aliases (BusyBox aliases for ls/grep)
alias ls='ls --color=auto'
alias grep='grep --color=auto'
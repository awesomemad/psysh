USER_PATH="\u@\h:\w"

build_prompt() {
    local EXIT="$?"
    local TOWER="(${MSYSTEM,,})"
    local GIT_INFO=$(get_git_info)

    # ZERO-FORK TIME: Use Bash built-in printf instead of the 'date' command
    printf -v DATE_TIME '%(%H:%M:%S)T' -1

    # Quantum Success/Failure Check for the Psi symbol

    local PSI=$GREENψ
    if [ $EXIT -ne 0 ]; then PSI=$RED∅; fi

    # The Final PS1
    PS1="\n${PROMPTCOLORD}█${PROMPTCOLORE}█${PROMPTCOLORF}█ ${M_VOID}${TOWER} ${M_WHITE}${USER_PATH}${GIT_INFO} ${M_VOID}at ${M_NOLAN}${DATE_TIME}\n${PROMPTCOLORA}█${PROMPTCOLORB}█${PROMPTCOLORC}█ ${PSI} ${M_RAIN}"
}

PROMPT_COMMAND=build_prompt

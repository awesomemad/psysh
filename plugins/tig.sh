get_git_info() {
    if [ -f .git/HEAD ]; then
        local branch=$(< .git/HEAD)
        # Extract branch name from "ref: refs/heads/master"
        echo -e " ${M_VOID}on ${M_NOLAN}${branch##*/}"
    fi
}

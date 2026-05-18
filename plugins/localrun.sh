command_not_found_handle() {
    if [[ -x "./$1" ]]; then
        "./$1" "${@:2}"
        return
    fi

    if [[ -x "./$1.exe" ]]; then
        "./$1.exe" "${@:2}"
        return
    fi

    printf 'Command not found: %s\n' "$1"
    return 127
}

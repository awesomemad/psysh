# --- psh ---
PSH_ORIGINAL_PATH="${PSH_ORIGINAL_PATH:-$PATH}"
PSH_ORIGINAL_MSYSTEM="${PSH_ORIGINAL_MSYSTEM:-$MSYSTEM}"

psh() {
    case "$1" in
        ucrt)
            export MSYSTEM=UCRT64
            export PATH="/ucrt64/bin:/usr/bin:$PSH_ORIGINAL_PATH"
            export CC=gcc
            export CXX=g++
            ;;

        clang)
            export MSYSTEM=CLANG64
            export PATH="/clang64/bin:/usr/bin:$PSH_ORIGINAL_PATH"
            export CC=clang
            export CXX=clang++
            ;;

        clangarm)
            export MSYSTEM=CLANGARM64
            export PATH="/clangarm64/bin:/usr/bin:$PSH_ORIGINAL_PATH"
            export CC=clang
            export CXX=clang++
            ;;

        mingw)
            export MSYSTEM=MINGW64
            export PATH="/mingw64/bin:/usr/bin:$PSH_ORIGINAL_PATH"
            export CC=gcc
            export CXX=g++
            ;;

        msys)
            export MSYSTEM=MSYS
            export PATH="/usr/bin:$PSH_ORIGINAL_PATH"
            ;;

        reset)
            export PATH="$PSH_ORIGINAL_PATH"
            export MSYSTEM="$PSH_ORIGINAL_MSYSTEM"
            unset CC CXX
            ;;

        *)
            echo "Usage: psh {ucrt|clang|clangarm|mingw|msys|reset}"
            return 1
            ;;
    esac

    echo "→ psysh environment: $MSYSTEM"
}

sys() {
    local cmd="search" # Default mode
    local pkg="$1"

    # Flag detection
    case "$1" in
        -i|--install) cmd="install"; pkg="$2" ;;
        -u|--update)  cmd="update";  pkg="$2" ;; # Modified to handle both global and specific
        -*) echo "Usage: sys [pkg] | sys -i [pkg] | sys -u (all) | sys -u [pkg]"; return 1 ;;
    esac

    case "$cmd" in
        search)
            echo -e "\n\e[1;34m[1/4] MSYS2 (UCRT64)...\e[0m"
            pacman -Ss "$pkg" || true
            echo -e "\n\e[1;34m[2/4] Chocolatey...\e[0m"
            choco search "$pkg" || true
            echo -e "\n\e[1;34m[3/4] Winget...\e[0m"
            winget search "$pkg" || true
            echo -e "\n\e[1;34m[4/4] Scoop...\e[0m"
            scoop search "$pkg" || true
            ;;

        install)
            if [ -z "$pkg" ]; then echo "Specify a package name."; return 1; fi
            echo -e "\n\e[1;32mAttempting to install '$pkg'...\e[0m"
            # Try UCRT64 first, then base MSYS2, then Windows managers
            pacman -S "mingw-w64-ucrt-x86_64-$pkg" --noconfirm 2>/dev/null || \
            pacman -S "$pkg" --noconfirm 2>/dev/null || \
            winget install "$pkg" || \
            choco install "$pkg" -y || \
            scoop install "$pkg" || \
            echo -e "\e[1;31mFinished. Verify results above.\e[0m"
            ;;

        update)
            if [ -z "$pkg" ]; then
                # Global Update Mode
                echo -e "\n\e[1;35m--- Global Update Protocol Initiated ---\e[0m"
                echo "Updating MSYS2..." && pacman -Syu --noconfirm || true
                echo "Updating Winget..." && winget upgrade --all || true
                echo "Updating Chocolatey..." && choco upgrade all -y || true
                echo "Updating Scoop..." && scoop update --all || true
            else
                # Targeted Update Mode
                echo -e "\n\e[1;32mTargeting '$pkg' for updates...\e[0m"
                # MSYS2/Pacman uses -S to update a single package
                pacman -S "mingw-w64-ucrt-x86_64-$pkg" --noconfirm 2>/dev/null || \
                pacman -S "$pkg" --noconfirm 2>/dev/null || \
                winget upgrade "$pkg" || \
                choco upgrade "$pkg" -y || \
                scoop update "$pkg" || \
                echo -e "\e[1;31mUpdate complete or package not found.\e[0m"
            fi
            ;;
    esac
}

cleanup() {
    echo "Cleaning Pacman cache..." && pacman -Sc --noconfirm
    echo "Cleaning Scoop cache..." && scoop cleanup "*"
    echo "Vacuuming Bash history..." && history -w && history -c && history -r
}

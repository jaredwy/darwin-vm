#!/bin/bash
set -euo pipefail

# macOS 27 deprecated `hdiutil attach`; `diskutil image` replaces it but exists
# only on macOS 26+. Prefer it when present, fall back to hdiutil otherwise.
# Drop the hdiutil fallback once macOS < 26 is no longer supported.
use_diskutil_image() {  # true on macOS 26+, where the `diskutil image` verb exists
    local major
    major="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
    [[ "${major}" =~ ^[0-9]+$ ]] && (( major >= 26 ))
}

dmg_attach() { # owners(on|off) mountpoint image
    if use_diskutil_image; then
        local mo=owners; [[ "$1" == off ]] && mo=noowners
        diskutil image attach "$3" --mountOptions "$mo" --mountPoint "$2"
    else
        hdiutil attach -owners "$1" -mountpoint "$2" "$3"
    fi
}

dmg_detach() { # mountpoint
    if use_diskutil_image; then diskutil eject "$1"; else hdiutil detach "$1"; fi
}

fixup_perms() {
    local ramdisk="${1}"
    livemount="$(mktemp -d)"

    if [[ -z "${livemount}" || ! -d "${livemount}" ]]; then
        echo "something's wrong with the livemount, stopping here"
        exit 1
    fi

    if ! dmg_attach on "${livemount}" "${ramdisk}"; then
        echo "mount failed"
        rmdir "${livemount}"
        exit 1
    fi

    echo "mounted ${ramdisk} on ${livemount}"
    trap 'dmg_detach "${livemount}"; rmdir "${livemount}"' EXIT

    echo "This will run: sudo chown -R root:wheel ${livemount}/bin ${livemount}/System ${livemount}/libexec"
    read -r -p "Are you sure? (y/n) " response
    echo "${response}"

    case "${response}" in
        [Yy])
            sudo chown -R root:wheel "${livemount}/bin" "${livemount}/System"

            if [[ -d "${livemount}/libexec" ]]; then
                sudo chown -R root:wheel "${livemount}/libexec"
            fi
            echo "done!"
            ;;
        *)
            echo "skipping permission fixes"
            ;;
    esac
}

main() {
    if [[ -z "${1:-}" ]]; then
        echo "usage: fix_perms.sh [ramdisk.dmg]"
        exit 1
    fi

    if [[ "$(uname)" != "Darwin" ]]; then
        echo "you need to run this on a Mac"
        exit 1
    fi

    fixup_perms "${1}"
}

main "$@"

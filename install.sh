#!/bin/sh
# Install the latest macOS release. No Go toolchain is required.
set -eu

fail() { printf 'declutter: %s\n' "$*" >&2; exit 1; }

main() {
    [ "$(uname -s)" = Darwin ] || fail 'Only macOS is supported at this time.'
    case "$(uname -m)" in
        arm64) arch=arm64 ;;
        x86_64) arch=amd64 ;;
        *) fail 'Unsupported Mac architecture; use Apple Silicon or Intel.' ;;
    esac

    for tool in curl tar shasum install mktemp; do
        command -v "$tool" >/dev/null 2>&1 || fail "Required command not found: $tool"
    done

    repository=https://github.com/michaelmjhhhh/declutter
    release_version=${DECLUTTER_VERSION:-}
    if [ -z "$release_version" ]; then
        release_url=$(curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "$repository/releases/latest") || fail 'Could not find the latest release.'
        release_version=${release_url##*/}
    fi
    case "$release_version" in
        v[0-9]*) ;;
        *) fail 'Invalid release version; expected a tag such as v0.1.0.' ;;
    esac
    case "$release_version" in *[!a-zA-Z0-9._-]*) fail 'Invalid characters in release version.' ;; esac

    install_dir=${INSTALL_DIR:-/usr/local/bin}
    case "$install_dir" in /*) ;; *) fail 'INSTALL_DIR must be an absolute path.' ;; esac
    workdir=$(mktemp -d "${TMPDIR:-/tmp}/declutter.XXXXXX")
    trap 'rm -rf "$workdir"' 0
    trap 'exit 1' HUP INT TERM
    archive="declutter_darwin_${arch}.tar.gz"
    download="$repository/releases/download/$release_version"

    printf 'Downloading declutter %s for macOS (%s)…\n' "$release_version" "$arch"
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$download/$archive" -o "$workdir/$archive" || fail 'Binary download failed.'
    curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$download/checksums.txt" -o "$workdir/checksums.txt" || fail 'Checksum download failed.'
    awk -v name="$archive" '$2 == name { print }' "$workdir/checksums.txt" > "$workdir/selected.sha256"
    [ "$(wc -l < "$workdir/selected.sha256" | tr -d ' ')" = 1 ] || fail 'Release checksum is missing or ambiguous.'
    (cd "$workdir" && shasum -a 256 -c selected.sha256) || fail 'Checksum verification failed; nothing was installed.'
    tar -xzf "$workdir/$archive" -C "$workdir" declutter || fail 'Could not extract the executable.'
    [ -f "$workdir/declutter" ] && [ ! -L "$workdir/declutter" ] || fail 'Release executable is missing or invalid.'

    if mkdir -p "$install_dir" 2>/dev/null && [ -w "$install_dir" ]; then
        install -m 755 "$workdir/declutter" "$install_dir/declutter"
    else
        command -v sudo >/dev/null 2>&1 || fail "Cannot write to $install_dir; set INSTALL_DIR to a writable directory."
        printf 'Installing in %s (administrator access required)…\n' "$install_dir"
        sudo mkdir -p "$install_dir"
        sudo install -m 755 "$workdir/declutter" "$install_dir/declutter"
    fi
    printf '\nInstalled declutter %s → %s/declutter\n' "$release_version" "$install_dir"
    case ":$PATH:" in
        *":$install_dir:"*) printf 'Run: declutter\n' ;;
        *) printf 'Add this directory to your shell PATH: %s\n' "$install_dir" ;;
    esac
}

main "$@"

#!/usr/bin/env bash
#
# Install a specific pandoc release, or "latest", on a CI runner.
#
#   tests/install-pandoc.sh 3.1.3
#   tests/install-pandoc.sh latest
#
# Pandoc's own GitHub releases are used directly rather than a third-party
# action, so the supply chain here is jgm/pandoc and nothing else. Note that
# 2.17 ships no macOS build -- only Linux can test the documented floor.
#
set -euo pipefail

ver="${1:?usage: install-pandoc.sh VERSION|latest}"
if [ "$ver" = latest ]; then
  # Resolved from the releases redirect, not api.github.com. The anonymous
  # API allows 60 requests an hour per IP, CI runners share outbound IPs, and
  # the resulting 403 fails the build for reasons unrelated to the code --
  # intermittently, which is worse. The redirect carries no such limit.
  ver=$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' \
        "https://github.com/jgm/pandoc/releases/latest" | sed 's|.*/tag/||')
  [ -n "$ver" ] || { echo "could not resolve the latest pandoc release" >&2; exit 1; }
  echo "latest resolves to $ver"
fi

case "$(uname -s)" in
  Linux)
    curl -fsSL --retry 3 -o /tmp/pandoc.deb \
      "https://github.com/jgm/pandoc/releases/download/$ver/pandoc-$ver-1-amd64.deb"
    sudo dpkg -i /tmp/pandoc.deb >/dev/null
    ;;
  Darwin)
    arch=arm64
    [ "$(uname -m)" = "x86_64" ] && arch=x86_64
    curl -fsSL --retry 3 -o /tmp/pandoc.zip \
      "https://github.com/jgm/pandoc/releases/download/$ver/pandoc-$ver-$arch-macOS.zip"
    rm -rf /tmp/pandoc-install
    unzip -qo /tmp/pandoc.zip -d /tmp/pandoc-install
    # The directory inside the archive has carried different names across
    # releases, so locate bin/ rather than assuming its path.
    bindir=$(find /tmp/pandoc-install -type d -name bin | head -1)
    [ -n "$bindir" ] || { echo "no bin/ inside the pandoc archive" >&2; exit 1; }
    export PATH="$bindir:$PATH"
    [ -n "${GITHUB_PATH:-}" ] && echo "$bindir" >> "$GITHUB_PATH"
    ;;
  *)
    echo "unsupported platform: $(uname -s)" >&2; exit 1 ;;
esac

pandoc --version | head -1

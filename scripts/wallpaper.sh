#!/usr/bin/env bash
# Wallpaper picker for niri, using awww for animated transitions.
#   wallpaper.sh          pick a wallpaper from a rofi thumbnail grid and apply it
#   wallpaper.sh restore  start awww and apply the saved wallpaper (used at startup)
#   wallpaper.sh thumbs   generate missing previews without opening the picker

dirs=(
    "$HOME/.mydotfiles/com.ml4w.dotfiles/.config/ml4w/wallpapers"
    "$HOME/Wallpapers"
)
default="$HOME/.mydotfiles/com.ml4w.dotfiles/.config/ml4w/wallpapers/Nocturne-of-Steel-and-Glass.jpg"
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
state="$cache/niri-wallpaper"
thumbs="$cache/niri-wallpaper-thumbs"
theme="$HOME/.config/niri/rofi/wallpaper.rasi"

thumb_path() {
    printf '%s/%s.png' "$thumbs" "$(printf '%s' "$1" | md5sum | cut -d' ' -f1)"
}

# Internal: build one preview (run in parallel by make_thumbs).
if [ "$1" = "make-thumb" ]; then
    out=$(thumb_path "$2")
    # jpeg:size lets ImageMagick decode large JPEGs at reduced size, which is much faster.
    magick -define jpeg:size=880x560 "$2[0]" -thumbnail 440x280^ -gravity center \
        -extent 440x280 "$out.tmp.png" 2>/dev/null && mv "$out.tmp.png" "$out"
    rm -f "$out.tmp.png"
    exit 0
fi

ensure_daemon() {
    awww query >/dev/null 2>&1 && return
    # 9>&- keeps the daemon from inheriting (and holding forever) the picker lock.
    awww-daemon >/dev/null 2>&1 9>&- &
    disown
    for _ in $(seq 50); do
        awww query >/dev/null 2>&1 && return
        sleep 0.1
    done
}

apply() {
    ensure_daemon
    awww img "$1" "${@:2}"
    # swaybg (from the old setup) would cover awww, so stop it once awww is drawing.
    pkill -x swaybg 2>/dev/null
}

if [ "$1" = "restore" ]; then
    wallpaper=$(cat "$state" 2>/dev/null)
    [ -f "$wallpaper" ] || wallpaper="$default"
    apply "$wallpaper" --transition-type fade --transition-duration 1
    exit 0
fi

# Only one picker at a time; extra key presses while it's open or loading are ignored.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/niri-wallpaper-picker.lock"
flock -n 9 || exit 0

mapfile -t files < <(find "${dirs[@]}" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort)
[ ${#files[@]} -eq 0 ] && exit 1

# Generate missing or outdated previews in parallel.
mkdir -p "$thumbs"
missing=()
for f in "${files[@]}"; do
    t=$(thumb_path "$f")
    { [ ! -f "$t" ] || [ "$f" -nt "$t" ]; } && missing+=("$f")
done
if [ ${#missing[@]} -gt 0 ]; then
    [ "$1" != "thumbs" ] && notify-send -a Wallpaper -t 3000 "Generating previews…" \
        "${#missing[@]} new wallpapers, this only happens once."
    printf '%s\0' "${missing[@]}" | xargs -0 -n1 -P "$(nproc)" "$0" make-thumb
fi
[ "$1" = "thumbs" ] && exit 0

choice=$(for f in "${files[@]}"; do
    name="${f##*/}"
    printf '%s\0icon\x1f%s\n' "${name%.*}" "$(thumb_path "$f")"
done | rofi -dmenu -i -show-icons -format i -p "󰸉 " -theme "$theme")
[ -z "$choice" ] && exit 0

selected="${files[$choice]}"
printf '%s\n' "$selected" >"$state"
apply "$selected" \
    --transition-type grow \
    --transition-pos center \
    --transition-duration 1.2 \
    --transition-fps 120 \
    --transition-bezier .43,1.19,1,.4

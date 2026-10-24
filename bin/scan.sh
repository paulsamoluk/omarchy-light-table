#!/usr/bin/env bash
# Light Table — index photo folders for the Omarchy bar widget.
#
#   scan.sh list <cacheDir> <limit> <sort> <depth> <dir>...
#   scan.sh warm <cacheDir> <limit> <sort> <depth> <dir>...
#
# <depth> is how many directory levels to look at, counting the folder itself:
# 1 = only the folder, 6 = up to five levels of subfolders (photographers keep
# shoots in dated folders, so the widget asks for >1 by default).
#
# `list` prints one TSV row per image, newest first (or by name):
#   path <TAB> preview <TAB> filename <TAB> mtime <TAB> previewIsCached(0|1)
# `warm` prints nothing and only fills in the missing previews.
#
# Previews are cached by path + (size:mtime), so rescanning an unchanged
# folder decodes no images at all. Anything ImageMagick cannot read (a RAW
# without a delegate, a broken file) keeps its original path and the panel
# shows a file-type glyph instead of a thumbnail.

set -uo pipefail

mode=${1:-list}
cache=${2:-}
limit=${3:-600}
sort_mode=${4:-newest}
depth=${5:-6}
shift 5 || exit 0

[[ -n $cache ]] || exit 0
mkdir -p "$cache" || exit 0

exts=(jpg jpeg png gif bmp webp tif tiff heic heif avif cr2 cr3 nef arw dng raf orf rw2 pef srw nrw 3fr iiq mos)
match=()
for e in "${exts[@]}"; do
  match+=(-o -iname "*.${e}")
done
match=("${match[@]:1}")

collect() {
  local dir
  local depth_args=()
  (( depth > 0 )) && depth_args=(-maxdepth "$depth")

  for dir in "$@"; do
    [[ -d $dir ]] || continue
    # Prune hidden *entries inside* the folder rather than matching the full
    # path: `! -path '*/.*'` also threw away every file under a watched folder
    # that lives below a dot-directory (e.g. ~/.photos or ~/.local/share/...).
    find -L "$dir" ${depth_args[@]+"${depth_args[@]}"} \
      \( -name '.*' -prune \) -o \
      \( -type f \( "${match[@]}" \) -printf '%T@\t%s\t%p\n' \) 2>/dev/null
  done
}

select_rows() {
  if [[ $sort_mode == name ]]; then
    collect "$@" | sort -t $'\t' -k3,3f
  else
    collect "$@" | sort -t $'\t' -k1,1gr
  fi | awk -F'\t' '!seen[$3]++' | head -n "$limit"
}

# path + signature -> stable cache key. Remembered between runs so a rescan
# costs one `find` instead of a `stat` and `md5sum` per photo.
declare -A known=()
if [[ -r $cache/index.tsv ]]; then
  while IFS=$'\t' read -r p sig key; do
    [[ -n ${p:-} ]] && known["$p"]="$sig:$key"
  done < "$cache/index.tsv"
fi

key_for() {
  local path=$1 sig=$2 entry=${known[$1]:-}
  if [[ -n ${entry#*:} && ${entry%%:*} == "$sig" ]]; then
    printf '%s' "${entry#*:}"
    return 0
  fi
  printf '%s\t%s' "$path" "$sig" | md5sum | cut -c1-16
}

preview_for() {
  local path=$1 thumb=$2 tmp
  # The temp name must carry the .jpg extension (and an explicit `jpg:` prefix
  # on top): ImageMagick picks the encoder from the output name, so a temp file
  # called `<key>.jpg.tmp.123` made it fall back to the *input's* format — which
  # silently failed for every camera raw file.
  tmp="$thumb.tmp.$$.jpg"
  if timeout 30 magick "${path}[0]" -auto-orient -thumbnail '640x640^' \
      -gravity center -extent 640x640 -strip -quality 80 \
      -define jpeg:extent=150kb "jpg:$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$thumb" && return 0
  fi
  rm -f "$tmp"
  return 1
}

index=()
while IFS=$'\t' read -r mtime size path; do
  [[ -n ${path:-} && -f $path ]] || continue
  sig="$size:${mtime%%.*}"
  key=$(key_for "$path" "$sig")
  index+=("${path}"$'\t'"${sig}"$'\t'"${key}")
  thumb="$cache/$key.jpg"
  # Building previews belongs to `warm`: doing it here made the first list pass
  # over a new folder take minutes before the panel could show anything.
  [[ -f $thumb ]] || { [[ $mode == warm ]] && preview_for "$path" "$thumb"; }
  [[ $mode == warm ]] && continue
  if [[ -f $thumb ]]; then preview=$thumb; cached=1; else preview=$path; cached=0; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$preview" "${path##*/}" "${mtime%%.*}" "$cached"
done < <(select_rows "$@")

if [[ $mode == list && ${#index[@]} -gt 0 ]]; then
  # Merge into the existing index instead of replacing it: the bar can run more
  # than one instance of a widget (one per monitor, plus warm-up copies), and
  # when each wrote only what it had just scanned they deleted each other's
  # entries — and then each other's previews.
  tmp="$cache/index.tsv.$$"
  if [[ -r $cache/index.tsv ]]; then
    while IFS=$'\t' read -r p sig key; do
      [[ -n ${p:-} && -n ${key:-} && -f $p ]] && printf '%s\t%s\t%s\n' "$p" "$sig" "$key"
    done < "$cache/index.tsv" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s\n' "${index[@]}" >> "$tmp"
  # Newest line wins for a path that appears twice (this run's signature/key
  # must beat the stale one), so dedupe from the bottom.
  tac "$tmp" | awk -F'\t' '!seen[$1]++' | tac > "$tmp.2" && mv -f "$tmp.2" "$cache/index.tsv"
  rm -f "$tmp"

  # Drop previews nothing references any more (deleted, renamed, or moved out of
  # the folders). Six hours of grace so a warm pass that is building one right
  # now is never pulled out from under it.
  declare -A live=()
  while IFS=$'\t' read -r _ _ key; do
    [[ -n ${key:-} ]] && live["$key"]=1
  done < "$cache/index.tsv"
  now=$(date +%s)
  while IFS= read -r -d '' stale; do
    key=${stale##*/}; key=${key%.jpg}
    [[ -n ${live[$key]:-} ]] && continue
    mtime=$(stat -c %Y "$stale" 2>/dev/null) || continue
    (( now - mtime > 21600 )) && rm -f "$stale"
  done < <(find "$cache" -maxdepth 1 -name '*.jpg' -print0 2>/dev/null)
fi

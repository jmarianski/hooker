# Reverse lines of a file. Portable replacement for tac.
_hooker_reverse() {
    awk '{a[NR]=$0} END{for(i=NR;i>=1;i--)print a[i]}'
}

# Strip <hidden> tags from a string, return visible part only.
# Handles both single-line (<hidden>...</hidden> on one line) and multiline.
_hooker_strip_hidden() {
    echo "$1" | sed 's/<hidden>[^<]*<\/hidden>//g' | awk '
    /<hidden>/ { skip=1; next }
    /<\/hidden>/ { skip=0; next }
    !skip { print }
    '
}

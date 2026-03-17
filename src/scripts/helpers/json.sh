# Extract a JSON string field value. Usage: echo "$JSON" | _hooker_json_field "field_name"
_hooker_json_field() {
    sed -n 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Check if JSON contains a field with a specific value. Usage: echo "$JSON" | _hooker_json_match "field" "value"
_hooker_json_match() {
    grep -q "\"$1\"[[:space:]]*:[[:space:]]*\"*$2" 2>/dev/null
}

# JSON-escape stdin. No python3/perl dependency.
_hooker_json_escape() {
    awk '
    BEGIN { ORS=""; first=1 }
    {
        if (!first) printf "\\n"
        first=0
        gsub(/\\/, "\\\\")
        gsub(/"/, "\\\"")
        gsub(/\t/, "\\t")
        gsub(/\r/, "\\r")
        print
    }
    END { }
    ' | { IFS= read -r -d '' x || true; printf '"%s"' "$x"; }
}

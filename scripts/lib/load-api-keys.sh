# Sourced by env.sh. Parse literal .env assignments without executing shell code.
langacqbench_load_api_keys() {
    local env_file="$1" line key value prefix name line_number=0
    local -A file_keys=()
    if [[ -e "$env_file" ]]; then
        if [[ ! -f "$env_file" || ! -r "$env_file" ]]; then
            echo "API key env file must be a readable regular file: $env_file" >&2
            return 1
        fi
        while IFS= read -r line || [[ -n "$line" ]]; do
            line_number=$((line_number + 1))
            line="${line%$'\r'}"
            [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
            if [[ ! "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
                echo "Invalid .env assignment at $env_file:$line_number (expected KEY=value)" >&2
                return 1
            fi
            key="${BASH_REMATCH[2]}"
            value="${BASH_REMATCH[3]}"
            case "$key" in
                ANTHROPIC_API_KEY|GEMINI_API_KEY|APPTAINERENV_ANTHROPIC_API_KEY|APPTAINERENV_GEMINI_API_KEY) ;;
                *) continue ;;
            esac
            value="${value%"${value##*[![:space:]]}"}"
            case "$value" in
                \"*\") value="${value:1:${#value}-2}" ;;
                \'*\') value="${value:1:${#value}-2}" ;;
                *)
                    if [[ "$value" == [\"\']* || "$value" =~ [[:space:]] ]]; then
                        echo "Invalid .env value at $env_file:$line_number (quote the whole value; use separate comment lines)" >&2
                        return 1
                    fi
                    ;;
            esac
            file_keys["$key"]="$value"
        done < "$env_file"
    fi

    for name in ANTHROPIC_API_KEY GEMINI_API_KEY; do
        prefix="APPTAINERENV_$name"
        # Existing environment wins, including on a repeated source in a job.
        value="${!prefix:-}"
        [[ -n "$value" ]] || value="${!name:-}"
        [[ -n "$value" ]] || value="${file_keys[$prefix]:-}"
        [[ -n "$value" ]] || value="${file_keys[$name]:-}"
        if [[ -n "$value" ]]; then
            export "$prefix=$value"
        fi
    done
}

# ~/.local/libexec/cm-common.sh — shared directory browser for cm-* scripts
#
# Usage: source this file, then set variables and call browse_nav()
#
# Required caller setup (before calling browse_nav):
#   browse_ext_filter  — space-separated extensions, e.g. "png jpg jpeg"
#   browse_on_file()   — callback function, see below
#
# Optional overrides:
#   browse_label_dir   — printf template with %s for dir basename (default: ' 󰉋 %s 󰅂')
#   browse_label_file  — printf template with %s for file basename (default: ' 󰋩 %s')
#   browse_use_thumbs  — if true, append \x1f<thumb> to all labels; dirs w/o images are skipped
#   browse_show_add_all — if true, show "󰐚 Add all" button when files are present
#
# Caller sets these during browse_on_file to control navigation:
#   browse_select_idx   — preselect item by index on next re-list (takes priority)
#   browse_select_path  — preselect item by full path on next re-list
#
# browse_on_file(path, all_files...):
#   Return 0 — stay in browser, re-list same directory
#   Return 1 — exit browser (browse_nav returns 1)
#   Return 2 — re-list with browse_select_path (for cm-image rc=2 flow)

browse_nav() {
    local start_dir="$1"
    local theme="${2:-}"
    local dir="$start_dir"
    local _prev_dir="" _sel_idx="" _thumb=""
    local f e

    if ! declare -F browse_on_file &>/dev/null; then
        echo "cm-common.sh: browse_on_file() not defined by caller" >&2
        return 1
    fi

    while true; do
        local ids=() labels=() files=()

        # -- Directories --
        for f in "$dir"/*/; do
            [ -d "$f" ] || continue
            _thumb=""
            if [ "${browse_use_thumbs:-false}" = "true" ]; then
                _thumb=$(find "$f" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | head -1)
                [ -z "$_thumb" ] && continue
            fi
            ids+=("$f")
            local _label
            _label=$(printf "${browse_label_dir:- 󰉋 %s 󰅂}" "$(basename "$f")")
            if [ -n "$_thumb" ]; then
                _label="${_label}"$'\x1f'"${_thumb}"
            fi
            labels+=("$_label")
        done

        # -- Files --
        local ext_lc=""
        for e in ${browse_ext_filter:?browse_ext_filter not set}; do
            ext_lc="${ext_lc:+${ext_lc} }${e,,}"
        done

        for f in "$dir"/*; do
            [ -f "$f" ] || continue
            local ext="${f##*.}"
            ext="${ext,,}"
            local _matched=false
            for e in $ext_lc; do
                [ "$ext" = "$e" ] && { _matched=true; break; }
            done
            $_matched || continue
            ids+=("$f")
            local _label
            _label=$(printf "${browse_label_file:- 󰋩 %s}" "$(basename "$f")")
            if [ "${browse_use_thumbs:-false}" = "true" ]; then
                _label="${_label}"$'\x1f'"${f}"
            fi
            labels+=("$_label")
            files+=("$f")
        done

        # -- Selection resolution (caller override > prev_dir) --
        _sel_idx=""
        if [ -n "${browse_select_idx:-}" ]; then
            _sel_idx="$browse_select_idx"
            browse_select_idx=""
        elif [ -n "${browse_select_path:-}" ]; then
            for i in "${!ids[@]}"; do
                [ "${ids[$i]}" = "$browse_select_path" ] && { _sel_idx="$i"; break; }
            done
            browse_select_path=""
        elif [ -n "$_prev_dir" ]; then
            for i in "${!ids[@]}"; do
                [ "${ids[$i]}" = "$_prev_dir" ] && { _sel_idx="$i"; break; }
            done
            _prev_dir=""
        fi

        # -- Empty dir: go up --
        if [[ ${#ids[@]} -eq 0 ]]; then
            [[ "$dir" == "$start_dir" ]] && return 1
            _prev_dir="${dir%/}/"
            dir="$(dirname "$dir")"
            continue
        fi

        # -- Build menu --
        local -a _menu_lines=()
        local _add_all_adj=0
        if [ "${browse_show_add_all:-false}" = "true" ] && [ ${#files[@]} -gt 0 ]; then
            _menu_lines+=("󰐚 Add all")
            _add_all_adj=1
        fi
        for _label in "${labels[@]}"; do
            _menu_lines+=("$_label")
        done

        local -a theme_opt=()
        [ -n "$theme" ] && theme_opt=(-c "$theme")

        local _sel
        _sel=$(printf '%s\n' "${_menu_lines[@]}" \
            | tiny-cmenush "${theme_opt[@]}" -p "$(basename "$dir")" --format i ${_sel_idx:+--select $_sel_idx})

        _sel_idx=""

        # -- Escape: go up --
        if [[ -z "$_sel" ]]; then
            [[ "$dir" == "$start_dir" ]] && return 1
            _prev_dir="${dir%/}/"
            dir="$(dirname "$dir")"
            continue
        fi

        # -- Add all --
        if [ "$_add_all_adj" -gt 0 ] && [ "$_sel" -eq 0 ]; then
            browse_on_file "__add_all__" "${files[@]}"
            local _rc=$?
            [ $_rc -eq 1 ] && return 1
            continue
        fi

        local _action="${ids[$((_sel - _add_all_adj))]:-}"
        [[ -z "$_action" ]] && continue

        # -- Directory: descend --
        [ -d "$_action" ] && { dir="$_action"; continue; }

        # -- File: call callback --
        browse_on_file "$_action" "${files[@]}"
        local _rc=$?
        [ $_rc -eq 1 ] && return 1
        # _rc=0 or 2: re-list same dir
    done
}

# Keyboard LED hooks for zsh
# Source this from ~/.zshrc:  source ~/playground/keyboard/shell/keyboard_hooks.zsh

KEYBOARD_CMD_THRESHOLD=${KEYBOARD_CMD_THRESHOLD:-3}  # seconds before yellow breathe starts
KEYBOARD_BIN="$HOME/playground/keyboard/bin/dygma"

_keyboard_cmd_start=0
_keyboard_sentinel=""

# Double-fork: outer subshell exits immediately, inner process is adopted by
# init and runs fully detached — the shell never tracks it, no job messages.
_keyboard_breathe_delayed() {
    local sentinel=$1
    (
        (
            sleep "$KEYBOARD_CMD_THRESHOLD"
            if [[ -f "$sentinel" ]]; then
                rm -f "$sentinel"
                "$KEYBOARD_BIN" breathe underglow yellow --force >/dev/null 2>&1
            fi
        ) &
    )
}

_keyboard_preexec() {
    [[ $1 == exit || $1 == logout ]] && return
    _keyboard_cmd_start=$SECONDS
    _keyboard_sentinel=$(mktemp)
    _keyboard_breathe_delayed "$_keyboard_sentinel"
}

_keyboard_precmd() {
    local exit_code=$?
    [[ $_keyboard_cmd_start -eq 0 ]] && return
    local elapsed=$(( SECONDS - _keyboard_cmd_start ))
    _keyboard_cmd_start=0

    # Remove sentinel to cancel pending breathe (if sleep hasn't fired yet).
    if [[ -n $_keyboard_sentinel ]]; then
        rm -f "$_keyboard_sentinel" 2>/dev/null
        _keyboard_sentinel=""
    fi

    if [[ $exit_code -ne 0 ]]; then
        "$KEYBOARD_BIN" cancel-section underglow >/dev/null 2>&1
        "$KEYBOARD_BIN" flash all red 5 --force >/dev/null 2>&1
    elif (( elapsed >= KEYBOARD_CMD_THRESHOLD )); then
        "$KEYBOARD_BIN" cancel-section underglow >/dev/null 2>&1
        "$KEYBOARD_BIN" flash all green 5 --force >/dev/null 2>&1
    fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _keyboard_preexec
add-zsh-hook precmd  _keyboard_precmd

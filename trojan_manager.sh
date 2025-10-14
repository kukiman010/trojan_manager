#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

CONFIG="./config.json"
USERS="./users.json"
LOG="./trojan_manager.log"

export LC_ALL=C  # To avoid problematic locale warnings

# Root check
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Root privileges are required to run this script!${NC}"
  exit 1
fi

# jq check
if ! command -v jq >/dev/null; then
    echo -e "${RED}jq is not installed. ${GREEN}sudo apt install jq${NC}"
    exit 2
fi

# qrencode check
if ! command -v qrencode >/dev/null; then
    echo -e "${RED}qrencode is not installed. ${GREEN}sudo apt install qrencode${NC}"
    exit 2
fi

generate_password() {
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 10
}

create_qr() {
    local data="$1"
    if [[ -z "$data" ]]; then
        echo -e "${YELLOW}No data to generate QR code.${NC}"
        exit 4
    fi
    qrencode -t ANSIUTF8 "$data"
}

get_user_index() {
    local username="$1"
    jq -r --arg user "$username" 'map(.username) | index($user)' "$USERS"
}

get_user_password_key() {
    local username="$1"
    jq -r --arg name "${username}_" '.password[] | select(startswith($name))' "$CONFIG"
}

get_domain() {
    jq -r '.ssl.cert' "$CONFIG" | awk -F'/' '{print $(NF-1)}'
}

get_port() {
    jq -r '.local_port' "$CONFIG"
}

get_user_uri() {
    local username="$1"
    local user_key=$(get_user_password_key "$username")
    local domain=$(get_domain)
    local port=$(get_port)
    [[ -z "$user_key" || -z "$domain" || -z "$port" ]] && { echo "Incomplete config"; return 1; }
    echo "trojan://$user_key@$domain:$port?sni=$domain#$username"
}

sync_users_with_config() {
    # Collect username list from config.json
    mapfile -t conf_names < <(jq -r '.password[]' "$CONFIG" | grep '_' | sed 's/_.*//' | sort | uniq)
    if [[ ! -f "$USERS" ]]; then
        echo '[]' > "$USERS"
        return
    fi
    # Remove users not present in config.json
    jq --argjson names "$(printf '%s\n' "${conf_names[@]}" | jq -R . | jq -s .)" '
        map(select(.username as $u | $names | index($u) != null))
    ' "$USERS" > /tmp/users.json && mv /tmp/users.json "$USERS"
}

list_users() {
    sync_users_with_config
    jq -r 'to_entries[] | "\(.key+1)) \(.value.username)"' "$USERS"
}

add_user() {
    local username="$1"
    if jq -e ".[] | select(.username==\"$username\")" "$USERS" >/dev/null 2>&1; then
        echo -e "${YELLOW}User $username already exists.${NC}"
        exit 1
    fi
    local password=$(generate_password)
    local created=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
    local user_key="${username}_${password}"
    [ ! -f "$USERS" ] && echo '[]' > "$USERS"
    jq ". + [{\"username\": \"$username\", \"created\": \"$created\"}]" "$USERS" > /tmp/users.json && mv /tmp/users.json "$USERS"
    jq ".password += [\"$user_key\"]" "$CONFIG" > /tmp/config.json && mv /tmp/config.json "$CONFIG"
    local uri
    uri=$(get_user_uri "$username")
    echo "$uri"
    create_qr "$uri"
    echo "$(date --iso-8601=seconds) ADD $username $created " >> "$LOG"
}

regenerate_password() {
    local username="$1"
    local idx=$(get_user_index "$username")
    if [[ "$idx" == "null" ]]; then
        echo "User not found"
        return 1
    fi
    local old_key=$(get_user_password_key "$username")
    local new_password=$(generate_password)
    local new_key="${username}_${new_password}"
    jq --arg old "$old_key" --arg new "$new_key" \
       '.password |= map(if . == $old then $new else . end)' "$CONFIG" > /tmp/config.json && mv /tmp/config.json "$CONFIG"
    local now=$(date --utc +%Y-%m-%dT%H:%M:%SZ)
    echo "$(date --iso-8601=seconds) REGEN $username $now" >> "$LOG"
}

set_lock_date() {
    local username="$1"
    local date="$2"
    jq "map(if .username==\"$username\" then .+{\"locked\":\"$date\"} else . end)" "$USERS" > /tmp/users.json && mv /tmp/users.json "$USERS"
    echo "User $username is locked until $date."
}

delete_user() {
    local username="$1"
    local key=$(get_user_password_key "$username")
    jq --arg key "$key" '.password |= map(select(. != $key))' "$CONFIG" > /tmp/config.json && mv /tmp/config.json "$CONFIG"
    jq --arg name "$username" 'map(select(.username != $name))' "$USERS" > /tmp/users.json && mv /tmp/users.json "$USERS"
    echo "$(date --iso-8601=seconds) DELETE $username" >> "$LOG"
    echo "User $username has been deleted."
}

show_user_menu() {
    list_users
    echo ""
    read -p "Select user number: " num
    username=$(jq -r ".[$((num-1))].username" "$USERS")
    PS3="Choose an action for $username: "
    select opt in "Show QR" "Change password" "Show URI" "Lock by date" "Delete" "Exit"; do
        case $REPLY in
            1) uri=$(get_user_uri "$username"); create_qr "$uri";;
            2) regenerate_password "$username"; uri=$(get_user_uri "$username"); echo "$uri";;
            3) uri=$(get_user_uri "$username"); echo "$uri";;
            4) read -p "Lock date (YYYY-MM-DD): " lockdate; set_lock_date "$username" "$lockdate";;
            5) delete_user "$username";;
            *) break ;;
        esac
        break
    done
}

show_qr_for_user() {
    local username="$1"
    uri=$(get_user_uri "$username")
    create_qr "$uri"
}

show_user_config() {
    local username="$1"
    uri=$(get_user_uri "$username")
    echo "$uri"
}

restart_trojan_service() {
    echo -e "${YELLOW}Restarting trojan.service...${NC}"
    if systemctl restart trojan.service; then
        echo -e "${GREEN}trojan.service has been restarted successfully.${NC}"
    else
        echo -e "${RED}Failed to restart trojan.service!${NC}"
        exit 20
    fi
}


help() {
    echo "trojan_manager"
    echo -e "Available commands:\n"
    echo -e "\t-n, --new <user>   — create new user"
    echo -e "\t-l, --list         — list and manage users"
    echo -e "\t-qr <user>         — show QR code for user"
    echo -e "\t--config <user>    — show user trojan URI"
    echo -e "\t--restart, -r      — restart trojan.service"
    echo -e "\t--help             — this help"
    echo -e "\n"
}


case "$1" in
    --new|-n)
        [ -z "$2" ] && { echo "Username required"; exit 2; }
        add_user "$2"
        ;;
    --list|-l)
        show_user_menu
        ;;
    --qr)
        [ -z "$2" ] && { echo "Username required"; exit 2; }
        show_qr_for_user "$2"
        ;;
    --config)
        [ -z "$2" ] && { echo "Username required"; exit 2; }
        show_user_config "$2"
        ;;
    --restart|-r)
        restart_trojan_service
        ;;
    --help)
        help
        ;;
    *)
        help
        ;;
esac


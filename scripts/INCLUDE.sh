#!/bin/bash

# Enable strict mode for better error handling
set -euo pipefail
IFS=$'\n\t'

# Global variables for configuration with improved type declaration
declare -A CONFIG
CONFIG=(
    ["MAX_RETRIES"]=3
    ["RETRY_DELAY"]=2
    ["SPINNER_INTERVAL"]=0.1
    ["DEBUG"]=false
)

# Cleanup function
cleanup() {
    printf "\e[?25h"  # Ensure cursor is visible
    kill $(jobs -p) 2>/dev/null || true
}

# Set up cleanup trap
trap cleanup EXIT

# Enhanced color setup with dynamic terminal capability detection
setup_colors() {
    if [ -t 1 ] && tput colors &>/dev/null && [ "$(tput colors)" -ge 8 ]; then
        PURPLE=$(tput setaf 5)
        BLUE=$(tput setaf 4)
        GREEN=$(tput setaf 2)
        YELLOW=$(tput setaf 3)
        RED=$(tput setaf 1)
        MAGENTA=$(tput setaf 5)
        CYAN=$(tput setaf 6)
        RESET=$(tput sgr0)
        BOLD=$(tput bold)
        UL=$(tput smul)
    else
        PURPLE="" BLUE="" GREEN="" YELLOW="" RED="" MAGENTA="" CYAN="" RESET="" BOLD="" UL=""
    fi

    # Export readonly variables for logging
    readonly STEPS="[${PURPLE}STEPS${RESET}]"
    readonly INFO="[${BLUE}INFO${RESET}]"
    readonly SUCCESS="[${GREEN}SUCCESS${RESET}]"
    readonly WARNING="[${YELLOW}WARNING${RESET}]"
    readonly ERROR="[${RED}ERROR${RESET}]"
    readonly BFR="\\r\\033[K"
    readonly HOLD=" "
    readonly TAB="  "
}

# Enhanced logging function
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Output to console if not in quiet mode
    case "$level" in
        "ERROR")   echo -e "${ERROR} $message" >&2 ;;
        "WARNING") echo -e "${WARNING} $message" ;;
        "SUCCESS") echo -e "${SUCCESS} $message" ;;
        "INFO")    echo -e "${INFO} $message" ;;
        *)         echo -e "${INFO} $message" ;;
    esac
}

# Enhanced spinner with better process management
spinner() {
    local pid=$1
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local colors=("\033[31m" "\033[33m" "\033[32m" "\033[36m" "\033[34m" "\033[35m")
    
    printf "\e[?25l"  # Hide cursor
    
    while kill -0 $pid 2>/dev/null; do
        for ((i = 0; i < ${#frames[@]}; i++)); do
            printf "\r ${colors[i]}%s${RESET}" "${frames[i]}"
            sleep "${CONFIG[SPINNER_INTERVAL]}"
        done
    done
    
    printf "\e[?25h"  # Show cursor
    wait $pid  # Wait for process to finish and get exit status
    return $?
}

# Enhanced command installation with better error handling
cmdinstall() {
    local cmd="$1"
    local desc="${2:-$cmd}"
    
    log "INFO" "Installing: $desc"
    
    # Run command in background and capture PID
    eval "$cmd" 2>&1 &
    local cmd_pid=$!
    
    # Start spinner
    spinner $cmd_pid
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log "SUCCESS" "$desc installed successfully"
        [ "${CONFIG[DEBUG]}" = true ]
    else
        log "ERROR" "Failed to install $desc"
        return 1
    fi
}

# Enhanced dependency checking with version comparison
check_dependencies() {
    local -A dependencies=(
        ["aria2"]="aria2c --version | grep -oP 'aria2 version \K[\d\.]+'"
        ["curl"]="curl --version | grep -oP 'curl \K[\d\.]+'"
        ["tar"]="tar --version | grep -oP 'tar \K[\d\.]+'"
        ["gzip"]="gzip --version | grep -oP 'gzip \K[\d\.]+'"
        ["unzip"]="unzip -v | grep -oP 'UnZip \K[\d\.]+'"
        ["git"]="git --version | grep -oP 'git version \K[\d\.]+'"
        ["wget"]="wget --version | grep -oP 'GNU Wget \K[\d\.]+'"
    )
    
    log "STEPS" "Checking system dependencies..."
    
    # Update package lists with error handling
    if ! sudo apt-get update -qq &>/dev/null; then
        log "ERROR" "Failed to update package lists"
        return 1
    fi
    
    for pkg in "${!dependencies[@]}"; do
        local version_cmd="${dependencies[$pkg]}"
        local installed_version
        
        if ! installed_version=$(eval "$version_cmd" 2>/dev/null); then
            log "WARNING" "Installing $pkg..."
            if ! sudo apt-get install -y "$pkg" &>/dev/null; then
                log "ERROR" "Failed to install $pkg"
                return 1
            fi
            installed_version=$(eval "$version_cmd")
            log "SUCCESS" "Installed $pkg version $installed_version"
        else
            log "SUCCESS" "Found $pkg version $installed_version"
        fi
    done
    
    log "SUCCESS" "All dependencies are satisfied!"
}

# Enhanced download function with retry mechanism and better error handling
ariadl() {
    if [ "$#" -lt 1 ]; then
        echo -e "${ERROR} Usage: ariadl <URL> [OUTPUT_FILE]"
        return 1
    fi

    echo -e "${STEPS} Aria2 Downloader"

    local URL OUTPUT_FILE OUTPUT_DIR OUTPUT
    URL=$1
    local RETRY_COUNT=0
    local MAX_RETRIES=3

    if [ "$#" -eq 1 ]; then
        OUTPUT_FILE=$(basename "$URL")
        OUTPUT_DIR="."
    else
        OUTPUT=$2
        OUTPUT_DIR=$(dirname "$OUTPUT")
        OUTPUT_FILE=$(basename "$OUTPUT")
    fi

    if [ ! -d "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
    fi

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo -e "${INFO} Downloading: $URL (Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
        
        if [ -f "$OUTPUT_DIR/$OUTPUT_FILE" ]; then
            rm "$OUTPUT_DIR/$OUTPUT_FILE"
        fi
        
        aria2c -q -d "$OUTPUT_DIR" -o "$OUTPUT_FILE" "$URL"
        
        if [ $? -eq 0 ]; then
            echo -e "${SUCCESS} Downloaded: $OUTPUT_FILE"
            return 0
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo -e "${ERROR} Download failed. Retrying..."
                sleep 2
            fi
        fi
    done

    echo -e "${ERROR} Failed to download: $OUTPUT_FILE after $MAX_RETRIES attempts"
    return 1
}

# Enhanced package downloader with improved URL handling and validation
# Enhanced download function with proper array handling
download_packages() {
    local source="$1"
    shift
    local -a package_list=("$@")
    
    if [ ${#package_list[@]} -eq 0 ]; then
        log "ERROR" "No packages provided to download_packages"
        return 1
    fi
    
    log "STEPS" "Downloading packages from $source..."
    mkdir -p packages
    
    case "$source" in
        github)
            for entry in "${package_list[@]}"; do
                IFS="|" read -r filename base_url <<< "$entry"
                unset IFS  # Kembalikan IFS ke default setelah digunakan
            
                file_urls=$(curl -s "$base_url" | jq -r '.assets[].browser_download_url' | grep -E '\.(ipk|apk)$' | grep "$filename" | head -1)
                
                if [ -z "$file_urls" ]; then
                    error_msg "Failed to retrieve package info for [$filename] from $base_url"
                    continue
                fi
            
                ariadl "$file_urls" "$(basename "$file_urls")"
            done
            ;;
            
        custom)
            for entry in "${package_list[@]}"; do
                IFS="|" read -r filename base_url <<< "$entry"
                
                if [[ -z "$filename" || -z "$base_url" ]]; then
                    log "ERROR" "Invalid package entry: $entry"
                    continue
                fi
                
                local patterns=(
                    "${filename}[^\"]*\.(ipk|apk)"
                    "${filename}_.*\.(ipk|apk)"
                    "${filename}.*\.(ipk|apk)"
                )
                
                local found_url=""
                for pattern in "${patterns[@]}"; do
                    found_url=$(curl -sL "$base_url" | \
                              grep -oP "(?<=\")${pattern}(?=\")" | \
                              sort -V | \
                              tail -n 1)
                    
                    if [ -n "$found_url" ]; then
                        if ! ariadl "${base_url}/${found_url}" "packages/${found_url}"; then
                            log "ERROR" "Failed to download: $filename"
                        fi
                        break
                    fi
                done
                
                [ -z "$found_url" ] && log "ERROR" "No matching file found: $filename"
            done
            ;;
            
        *)
            log "ERROR" "Invalid source: $source"
            return 1
            ;;
    esac
    
    return 0
}
# Initialize the script
setup_colors
main() {
    check_dependencies || exit 1
    # Add your main script logic here
}

# Run main function if script is not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

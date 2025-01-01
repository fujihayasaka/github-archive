# Reset
ANSI_RESET=$(printf '\033[0m')       # Text Reset

# Regular Colors
ANSI_FG_BLACK=$(printf '\033[0;30m')        # Black
ANSI_FG_RED=$(printf '\033[0;31m')          # Red
ANSI_FG_GREEN=$(printf '\033[0;32m')        # Green
ANSI_FG_YELLOW=$(printf '\033[0;33m')       # Yellow
ANSI_FG_BLUE=$(printf '\033[0;34m')         # Blue
ANSI_FG_PURPLE=$(printf '\033[0;35m')       # Purple
ANSI_FG_CYAN=$(printf '\033[0;36m')         # Cyan
ANSI_FG_WHITE=$(printf '\033[0;37m')        # White

fatal() {
  echo "${ANSI_FG_RED}error${ANSI_RESET}: " "$@" 1>&2
  exit 1
}

warn() {
  echo "${ANSI_FG_YELLOW}warning${ANSI_RESET}: " "$@" 1>&2
}

highlight() {
  message=$@
  echo "${ANSI_FG_YELLOW}$message${ANSI_RESET}"
}

confirm() {
  while true; do
    echo -n "$@ [Y/n]: "
    read response

    if [ -z "$response" ]; then
      return 0
    fi

    case "$response" in
      y|Y|yes|YES) return 0;;
      n|N|no|NO) return 1;;
      *) echo "Invalid response '$response'";;
    esac
  done
}

find_mysql() {
  MYSQL_PATH="mysql"
  if ! type -p mysql >/dev/null 2>&1; then
    BREW_MYSQL_PATH=$(brew --prefix "mysql@5.7")
    if [ -z "$BREW_MYSQL_PATH" ]; then
      fatal "Failed to find 'mysql' client :(."
    elif [ ! -d "$BREW_MYSQL_PATH" ]; then
      fatal "MySQL path '$BREW_MYSQL_PATH' doesn't exist."
    fi
    MYSQL_PATH="$BREW_MYSQL_PATH/bin/mysql"
  fi
  echo "$MYSQL_PATH"
}

find_sibling() {
    local path="$root/../$1"
    if [ -d "$path" ]; then
        echo "$( cd "$path" >/dev/null 2>&1 && pwd )"
    fi
}

check_for_homebrew() {
  if ! type brew >/dev/null 2>&1; then
    cmd='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo
    echo "Homebrew is required to run this command. Run the following command to install it before continuing:"
    echo
    echo "  $(highlight $cmd)"
    echo
    exit 1
  fi
}
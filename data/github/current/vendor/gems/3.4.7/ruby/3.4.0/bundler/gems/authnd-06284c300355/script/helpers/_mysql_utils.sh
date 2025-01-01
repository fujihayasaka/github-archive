function get_mysql_command() {
  MYSQL_CMD="mysql"

  if ! type mysql >/dev/null 2>&1; then
    if ! type brew >/dev/null 2>&1; then
        echo "this command requires either 'mysql', or 'brew' and 'jq' on your path :(" 1>&2
        exit 1
    fi

    formula_dir=$(find $(brew --prefix)/Cellar/mysql -type d -maxdepth 1 | tail -n 1)

    if [ -z "$formula_dir" ]; then
        echo "could not find 'mysql' formula installed :(" 1>&2
        exit 1
    fi

    if [ ! -d "$formula_dir" ]; then
        echo "could not find 'mysql' formula installed :(" 1>&2
        exit 1
    fi

    mysql_version=$(basename $formula_dir)
    echo ">> found mysql@v$mysql_version"
    if ! [[ $mysql_version =~ 8.\d+.\d+ ]]; then
      echo "expecting mysql version >= 8, < 9 (found $mysql_version)"
      exit 1
    fi

    MYSQL_CMD="$formula_dir/bin/mysql"

    if [ ! -x "$MYSQL_CMD" ]; then
        echo "could not find 'mysql' in '$MYSQL_CMD'" 1>&2
        exit 1
    fi
  fi

  echo "$MYSQL_CMD"
}

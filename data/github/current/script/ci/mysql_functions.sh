#!/bin/bash
# Shared MySQL container functions for CI scripts.
#
# To use these in your script, set WORKSPACE (or accept the default) and then:
#   source script/ci/mysql_functions.sh
#
# The following variables can be set before sourcing to override defaults:
#   WORKSPACE, MYSQL_DATA_DIR, MYSQL_VERSION, MYSQL_SOCKET

export MYSQL_WORKSPACE="${WORKSPACE:-/workspace/github}"
MYSQL_DATA_DIR="${MYSQL_DATA_DIR:-$MYSQL_WORKSPACE/tmp/mysql-data}"
MYSQL_VERSION="${MYSQL_VERSION:-$(cat "$MYSQL_WORKSPACE/config/mysql-version")}"
MYSQL_SOCKET="${MYSQL_SOCKET:-$MYSQL_WORKSPACE/tmp/mysqld/mysqld.sock}"

start_mysql_container() {
  mkdir -p "${MYSQL_WORKSPACE}/tmp/mysqld"
  mkdir -p "${MYSQL_DATA_DIR}/mysql-files"

  container_id=$(docker run -d \
    --name mysql \
    --user $UID \
    --ulimit nofile=1048576:1048576 \
    --network host \
    -e MYSQL_ALLOW_EMPTY_PASSWORD=1 \
    -v "${MYSQL_DATA_DIR}/mysql:/var/lib/mysql" \
    -v "${MYSQL_DATA_DIR}/mysql-files:/var/lib/mysql-files" \
    -v "${MYSQL_WORKSPACE}/tmp/mysqld:/var/run/mysqld" \
    -v "${MYSQL_WORKSPACE}/config/ci/mysql.cnf:/etc/mysql/conf.d/mysql.cnf" \
    -v "/etc/localtime:/etc/localtime" \
    mysql:$MYSQL_VERSION)

  if ! wait_for_mysql; then
    docker logs "${container_id}"
    exit 1
  fi

  echo "MySQL started"
  docker logs "${container_id}"
}

wait_for_mysql() {
  echo "Waiting for MySQL socket connection..."
  for i in {1..60}; do
    if mysql -u root -S "$MYSQL_SOCKET" --execute "SELECT 1" > /dev/null 2>&1; then
      echo "MySQL is accepting socket connections"
      break
    fi
    if [ $i -eq 60 ]; then
      echo "MySQL did not start accepting connections in time"
      return 1
    fi
    sleep 1
    echo "Waiting for MySQL socket connection... ($i/60)"
  done

  # Wait for TCP connection
  echo "Waiting for MySQL TCP connection..."
  for i in {1..30}; do
    if mysql -u root -h 127.0.0.1 --execute "SELECT 1" > /dev/null 2>&1; then
      echo "MySQL initialization is complete"
      return 0
    fi
    sleep 1
    echo "Waiting for MySQL TCP connection... ($i/30)"
  done

  echo "MySQL initialization did not complete in time"
  return 1
}

setup_mysql_root_user() {
  # Create the root user
  mysql -u root -S "$MYSQL_SOCKET" --execute "SELECT * FROM mysql.user"
  mysql -u root -S "$MYSQL_SOCKET" --execute "CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY ''"
  mysql -u root -S "$MYSQL_SOCKET" --execute "GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;"
  echo "Root user created"

  # Verify TCP connections work
  mysql -u root -h "127.0.0.1" --execute "SELECT 1"
  mysql -u root -h "127.0.0.1" --execute "SHOW VARIABLES LIKE '%ssl%'"
  mysql -u root -h "127.0.0.1" --execute "SHOW GLOBAL VARIABLES"
  mysql -u root -h "127.0.0.1" --execute "SELECT 1"
}

stop_mysql_container() {
  echo "Shutting down MySQL..."
  if docker exec mysql mysqladmin -u root shutdown; then
    echo "Waiting for MySQL to stop..."

    for i in {1..30}; do
      if ! mysql -u root -S "$MYSQL_SOCKET" --execute "SELECT 1" > /dev/null 2>&1; then
        echo "MySQL has stopped"
        break
      fi
      sleep 1
      echo "Waiting for MySQL to stop... ($i/30)"
    done
  else
    echo "MySQL shutdown command failed"
    docker logs mysql || true
  fi

  echo "Stopping MySQL container..."
  docker stop mysql || true
  docker rm mysql || true
}

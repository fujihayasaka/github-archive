#!/bin/bash

command="$1"
shift

usage="usage: $0 <bash|console|ernicorn|gitdaemon|nginx|resqued|sleep|timerd|unicorn> [args]"

function abort() {
    echo -e "$1"
    exit 1
}

if [ -z "$command" ]; then
    abort "$usage"
fi


cd /github || abort "couldn't cd /github"

case "$command" in
bash)
    exec bash "$@"
    ;;

console)
    exec bin/console "$@"
    ;;

ernicorn)
    exec bin/ernicorn config/ernicorn.rb "$@"
    ;;

gitdaemon)
    exec /usr/lib/git-core/git-daemon "$@"
    ;;

nginx)
    exec nginx "$@"
    ;;

resqued)
    mkdir -p log tmp/pids
    touch log/{production,resqued,exceptions}.log
    RESQUED_LOG_ARGS="-l log/resqued.log"
    exec bin/resqued $RESQUED_LOG_ARGS -p tmp/pids/resqued.pid config/resqued/github-environment.rb config/resqued/github-enterprise.rb "$@"
    ;;

sleep)
    exec /bin/sleep "$@"
    ;;

timerd)
    exec bin/timerd config/timers.enterprise.rb "$@"
    ;;

unicorn)
    mkdir -p log tmp/sockets
    exec bin/unicorn -c config/unicorn.rb "$@"
    ;;
*)
    abort "unsupported command $1\n$usage"
;;
esac

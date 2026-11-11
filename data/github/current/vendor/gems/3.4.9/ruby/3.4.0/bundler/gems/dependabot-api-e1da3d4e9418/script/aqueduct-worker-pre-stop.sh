#!/bin/sh
# This script runs inside an aqueduct worker pod to perform a graceful shutdown

if [ -z "$1" ]; then
  echo "Provide grace period. Ex: ./aqueduct-worker-pre-stop.sh 30"
  return
fi

# Signal aqueduct workers to stop accepting new jobs and to terminate
# after existing jobs complete. Waits up to grace-period - 5s for
# workers to exit.
# https://github.com/spraints/resqued/blob/7d8394cff76cfc8c39e3dc9086a05d5419834924/lib/resqued/quit-and-wait.rb
bundle exec resqued quit-and-wait /tmp/resqued.pid --grace-period "$1"
exitCode=$?
echo "quit-and-wait returned $exitCode"
if [ $exitCode -ne 0 ]; then
    # send SIGTERM to aqueduct workers to terminate any jobs that didn't
    # complete in the grace period
    echo "terminating aqueduct workers"
    pkill -f aqueduct
fi

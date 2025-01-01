#!/bin/bash

fold() {
  echo "%%%FOLD {$*}%%%"
}

end_fold() {
  echo "%%%END FOLD%%%"
}

run() {
  fold "$*"
  time "$@" 2>&1
  rc=$?
  end_fold
  if [ $rc -ne 0 ]; then
    exit $rc
  fi
}

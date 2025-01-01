package mysqlerrors

import (
	"github.com/go-sql-driver/mysql"
)

const (
	serverShutdownErrorCode   = 1053 // Server shutdown in progress
	deadlockErrorCode         = 1213 // MySQL deadlock error code
	queryInterruptedErrorCode = 1317 // Query execution was interrupted
	goneAwayErrorCode         = 2006 // MySQL server and/or Vitess dropped our connection
	lostConnectionErrorCode   = 2013 // Lost connection to MySQL server and/or Vitess
	doNotWaitForLockErrorCode = 3572 // MySQL deadlock error code for a query that uses NOWAIT
)

// ServerShutdownError returns a mysql.Error with the code 1053, indicating the
// server is shutting down. This can be retried.
func ServerShutdownError() error {
	return &mysql.MySQLError{Number: serverShutdownErrorCode}
}

// DeadlockError returns a mysql.MySQLError with the code 1213, representing a
// deadlock.
func DeadlockError() error {
	return &mysql.MySQLError{Number: deadlockErrorCode}
}

// QueryInterruptedError returns a mysql.Error with the code 1317, indicating the
// query was killed. Normally, this would be a query that should be optimized,
// but we are tolerating these in ingest for now.
//
// See: https://github.com/github/blackbird/issues/7013
func QueryInterruptedError() error {
	return &mysql.MySQLError{Number: queryInterruptedErrorCode}
}

// GoneAwayError returns a mysql.Error with the code 2006, indicating the
// server closed the connection for some reason.
func GoneAwayError() error {
	return &mysql.MySQLError{Number: goneAwayErrorCode}
}

// LostConnectionError returns a mysql.Error with the code 2013, indicating we
// lost the connection to the server.
func LostConnectionError() error {
	return &mysql.MySQLError{Number: lostConnectionErrorCode}
}

// NoWaitLockError returns a mysql.MySQLError with the code 3572, representing a
// query using NOWAIT that was aborted because of a lock.
func NoWaitLockError() error {
	return &mysql.MySQLError{Number: doNotWaitForLockErrorCode}
}

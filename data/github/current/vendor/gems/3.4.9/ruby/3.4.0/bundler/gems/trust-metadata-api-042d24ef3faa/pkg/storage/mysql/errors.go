package mysql

import (
	"errors"
	"fmt"
)

var ErrAttestationNotFound = errors.New("no attestation for given (purl, predicateType) exists")

// ErrMySQLConn represents an error created when the service cannot
// connect with MySQL successfully.
type ErrMySQLConn struct {
	wrapped error
}

func (e *ErrMySQLConn) Error() string {
	msg := "failed to connect with mysql"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrMySQLConn) Unwrap() error {
	return e.wrapped
}

// ErrMySQLClose represents an error created when the service cannot
// close the connection with MySQL successfully.
type ErrMySQLClose struct {
	wrapped error
}

func (e *ErrMySQLClose) Error() string {
	msg := "closed connection mysql with an error"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrMySQLClose) Unwrap() error {
	return e.wrapped
}

// ErrConvertToSQLC represents an error created when a struct representing data
// to be stored cannot be converted to SQLC, which is the type used
// to store data in MySQL.
type ErrConvertToSQLC struct {
	wrapped error
}

func (e *ErrConvertToSQLC) Error() string {
	msg := "failed to convert to SQLC"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrConvertToSQLC) Unwrap() error {
	return e.wrapped
}

// ErrConvertFromSQLC represents an error created when a SQLC type struct cannot
// converted into another struct used throughout the code.
type ErrConvertFromSQLC struct {
	wrapped error
	id      uint64
}

func (e *ErrConvertFromSQLC) Error() string {
	msg := fmt.Sprintf("converting from SQLC: id %d", e.id)
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrConvertFromSQLC) Unwrap() error {
	return e.wrapped
}

// ErrGetRecord represents an error created a record cannot be retreived
// from the database.
type ErrGetRecord struct {
	wrapped error
}

func (e *ErrGetRecord) Error() string {
	msg := "failed to retrieve attestation record from database"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrGetRecord) Unwrap() error {
	return e.wrapped
}

// ErrStoreRecord represents an error created a record cannot be stored in the database.
type ErrStoreRecord struct {
	wrapped error
}

func (e *ErrStoreRecord) Error() string {
	msg := "failed to store attestation record in database"
	if e.wrapped == nil {
		return msg
	}
	return fmt.Sprintf("%s: %s", msg, e.wrapped.Error())
}

func (e *ErrStoreRecord) Unwrap() error {
	return e.wrapped
}

func NewErrGetRecord(wrapped error) error {
	return &ErrGetRecord{wrapped}
}

package mysql

import (
	"errors"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestErrMySQLConn(t *testing.T) {
	cause := errors.New("1")
	err := ErrMySQLConn{wrapped: cause}
	assert.Equal(t, "failed to connect with mysql: 1", err.Error())
	assert.Equal(t, cause, err.Unwrap())
}

func TestErrMySQLClose(t *testing.T) {
	cause := errors.New("1")
	err := ErrMySQLClose{wrapped: cause}
	assert.Equal(t, "closed connection mysql with an error: 1", err.Error())
	assert.Equal(t, cause, err.Unwrap())
}

func TestErrConvertToSQLC(t *testing.T) {
	cause := errors.New("1")
	err := ErrConvertToSQLC{wrapped: cause}
	assert.Equal(t, "failed to convert to SQLC: 1", err.Error())
	assert.Equal(t, cause, err.Unwrap())
}

func TestErrConvertFromSQLC(t *testing.T) {
	cause := errors.New("1")
	err := ErrConvertFromSQLC{wrapped: cause, id: 123}
	assert.Equal(t, "converting from SQLC: id 123: 1", err.Error())
	assert.Equal(t, cause, err.Unwrap())
}

func TestErrGetRecord(t *testing.T) {
	cause := errors.New("1")
	err := ErrGetRecord{wrapped: cause}
	assert.Equal(t, "failed to retrieve attestation record from database: 1", err.Error())
	assert.Equal(t, cause, err.Unwrap())
}

func TestErrStoreRecord(t *testing.T) {
	cause := errors.New("1")
	err := ErrStoreRecord{wrapped: cause}
	assert.Equal(t, "failed to store attestation record in database: 1", err.Error())
	assert.Equal(t, cause, err.Unwrap())
}

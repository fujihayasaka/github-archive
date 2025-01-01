package types

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewTransactionContext(t *testing.T) {
	transactionState := []byte("test")
	respCtx := NewTransactionContext(transactionState)
	assert.Equal(t, respCtx, &TransactionContext{
		TransactionState: transactionState,
	})
}

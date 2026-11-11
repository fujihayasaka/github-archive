package types

func NewTransactionContext(transactionState []byte) *TransactionContext {
	ret := &TransactionContext{
		TransactionState: transactionState,
	}

	return ret
}

[&lt;&lt; Spokes API](../../../README.md)

# spokes-api/transactions/v1/transactions_api.proto



## Services

<a name="github.spokes.transactions.v1.TransactionsAPI"></a>

### TransactionsAPI

TransactionsAPI contains APIs for managing Spokes API write transactions.

<a name="github.spokes.transactions.v1.TransactionsAPI-BeginTransaction"></a>

#### BeginTransaction

BeginTransaction starts a transaction by creating a quarantine directory
into which new objects will be written. Returns the created
transaction_state.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.transactions.v1.TransactionsAPI/BeginTransaction`

<a name="github.spokes.transactions.v1.BeginTransactionRequest"></a>

##### BeginTransactionRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request_context contains the current transaction_state, which is used to configure the creation of a new transaction |



<a name="github.spokes.transactions.v1.BeginTransactionResponse"></a>

##### BeginTransactionResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| transaction_context | [github.spokes.types.v1.TransactionContext](../../types/v1/transaction_context.md#github.spokes.types.v1.TransactionContext) |  | transaction_context is the updated state after beginning the transaction. |



<a name="github.spokes.transactions.v1.TransactionsAPI-CommitTransaction"></a>

#### CommitTransaction

CommitTransaction commits an active transaction by committing the
quarantine objects to the main repository. Returns the updated
transaction_state.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.transactions.v1.TransactionsAPI/CommitTransaction`

<a name="github.spokes.transactions.v1.CommitTransactionRequest"></a>

##### CommitTransactionRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request context must include transaction state, which identifies the quarantine to commit. |



<a name="github.spokes.transactions.v1.CommitTransactionResponse"></a>

##### CommitTransactionResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| transaction_context | [github.spokes.types.v1.TransactionContext](../../types/v1/transaction_context.md#github.spokes.types.v1.TransactionContext) |  | transaction_context is the updated state after committing the transaction. |



<a name="github.spokes.transactions.v1.TransactionsAPI-RollbackTransaction"></a>

#### RollbackTransaction

RollbackTransaction cancels a transaction by removing the active
quarantine and all of the objects it contains.

##### Dev URL

`http://127.0.0.1:8081/twirp/github.spokes.transactions.v1.TransactionsAPI/RollbackTransaction`

<a name="github.spokes.transactions.v1.RollbackTransactionRequest"></a>

##### RollbackTransactionRequest




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| repository | [github.spokes.types.v1.Repository](../../types/v1/repository.md#github.spokes.types.v1.Repository) |  | repository is the repository to operate on. |
| request_context | [github.spokes.types.v1.RequestContext](../../types/v1/request_context.md#github.spokes.types.v1.RequestContext) |  | request context must include transaction state, which identifies the quarantine to roll back. |



<a name="github.spokes.transactions.v1.RollbackTransactionResponse"></a>

##### RollbackTransactionResponse




| Field | Type | Label | Description |
| ----- | ---- | ----- | ----------- |
| transaction_context | [github.spokes.types.v1.TransactionContext](../../types/v1/transaction_context.md#github.spokes.types.v1.TransactionContext) |  | transaction_context is the updated state after rolling back the transaction. |




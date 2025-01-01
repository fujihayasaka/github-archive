package query

import (
	"github.com/Azure/azure-kusto-go/azkustodata/kql"
)

type QueryProvider interface {
	Build() query
}

// Query should be in an isolated package to make sure it's read-only.
type query struct {
	query      *kql.Builder
	parameters *kql.Parameters
}

func newQuery(queryBuilder *kql.Builder, parameters *kql.Parameters) query {
	return query{
		query:      queryBuilder,
		parameters: parameters,
	}
}

func (q query) Query() *kql.Builder {
	// Copy the query to avoid modifying the original query.
	// The kql package checks that the pointer never changes and will panic if it does.
	copyQuery := *q.query
	return &copyQuery
}

func (q query) Parameters() *kql.Parameters {
	// There is no way to make parameters reado-only since the underlying map is a pointer.
	return q.parameters
}

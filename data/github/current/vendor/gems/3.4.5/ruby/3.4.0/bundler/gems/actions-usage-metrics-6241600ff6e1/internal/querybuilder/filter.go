package querybuilder

import (
	"github.com/github/actions-usage-metrics/lib/twirp/proto"
)

type KustoModelFilter struct {
	Field    KustoField
	Operator proto.FilterOperator
	Values   []any
}

package types

import (
	"fmt"

	"github.com/github/go-kvp"
)

// IDPair stores a DatabaseID and a GlobalID in cases where we need both, like
// in the case of a GitHub primitive that we may interact with via graphQL and
// other traditional interfaces.
type IDPair struct {
	DatabaseID int64
	GlobalID   GlobalID
}

// NilIDPair is an empty IDPair
var NilIDPair IDPair

func (id IDPair) IsZeroValue() bool {
	return id.GlobalID.IsZeroValue() && id.DatabaseID == 0
}

func (id IDPair) FieldsWithPrefix(prefix string) []kvp.Field {
	return []kvp.Field{
		kvp.String(fmt.Sprintf("%s_global_id", prefix), id.GlobalID.String()),
		kvp.Int(fmt.Sprintf("%s_database_id", prefix), int(id.DatabaseID)),
	}
}

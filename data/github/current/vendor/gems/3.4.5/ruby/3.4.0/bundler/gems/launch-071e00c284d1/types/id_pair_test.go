package types

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestIDPair_IsZeroValue(t *testing.T) {
	cases := []struct {
		Pair     IDPair
		Expected bool
	}{
		{NilIDPair, true},
		{IDPair{1, NilGlobalID}, false},
		{IDPair{0, GlobalID("foo")}, false},
		{IDPair{1, GlobalID("foo")}, false},
	}

	for _, c := range cases {
		s := fmt.Sprintf("(%d, %s)", c.Pair.DatabaseID, c.Pair.GlobalID)
		t.Run(s, func(tt *testing.T) {
			assert.Equal(tt, c.Pair.IsZeroValue(), c.Expected)
		})
	}
}

func TestIDPair_FieldsWithPrefix(t *testing.T) {
	ids := IDPair{1, GlobalID("foo")}

	fields := ids.FieldsWithPrefix("my")
	assert.Len(t, fields, 2)
	assert.Equal(t, fields[0].Key, "my_global_id")
	assert.Equal(t, fields[0].String(), "foo")
	assert.Equal(t, fields[1].Key, "my_database_id")
	assert.Equal(t, fields[1].String(), "1")
}

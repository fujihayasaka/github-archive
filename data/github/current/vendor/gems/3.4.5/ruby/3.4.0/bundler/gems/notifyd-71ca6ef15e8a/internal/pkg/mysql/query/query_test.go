package query

import (
	"testing"

	requirepkg "github.com/stretchr/testify/require"
)

func Test_IsNull(t *testing.T) {
	r := requirepkg.New(t)

	isNull := IsNull("user_id")
	sql, _, err := isNull.ToSql()

	r.NoError(err)
	r.Equal("user_id IS NULL", sql)
}

func Test_IsNotNull(t *testing.T) {
	r := requirepkg.New(t)

	isNotNull := IsNotNull("user_id")
	sql, _, err := isNotNull.ToSql()

	r.NoError(err)
	r.Equal("user_id IS NOT NULL", sql)
}

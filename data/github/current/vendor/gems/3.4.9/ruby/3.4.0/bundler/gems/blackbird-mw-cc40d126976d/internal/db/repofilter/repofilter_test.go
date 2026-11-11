package repofilter

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_Serialization(t *testing.T) {
	var filter F
	filter = Or(
		And(Deleted(), IDGreater(100)),
		Public(),
	)

	require.Equal(t, "((deleted == true AND id > 100) OR public == true)", filter.String())

	filter = And(
		Or(Any(), Deleted()),
		Public(),
	)

	require.Equal(t, "((true OR deleted == true) AND public == true)", filter.String())
}

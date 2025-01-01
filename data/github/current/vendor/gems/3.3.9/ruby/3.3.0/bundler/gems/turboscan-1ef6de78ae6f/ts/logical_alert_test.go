package ts

import (
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/stretchr/testify/require"
)

func TestGetFixAt(t *testing.T) {
	now := sqltime.Now()
	la := &LogicalAlert{
		LastObservedFixAt: &now,
	}

	// fix date is not reported when IsFixed is nil
	require.Nil(t, la.GetFixedAt())

	// fix date is not reported when IsFixed is false
	b := false
	la.IsFixed = &b
	require.Nil(t, la.GetFixedAt())

	// fix date is reported when IsFixed is false
	b = true
	require.NotNil(t, la.GetFixedAt())
	require.Equal(t, now, *la.GetFixedAt())

}

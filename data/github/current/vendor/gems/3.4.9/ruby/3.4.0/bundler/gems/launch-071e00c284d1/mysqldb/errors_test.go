package mysqldb

import (
	"testing"

	"github.com/github/go-exceptions"
	"github.com/go-sql-driver/mysql"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

func TestRollupDBError(t *testing.T) {
	tests := []struct {
		name           string
		err            error
		expectedRollup bool
		expectedInfo   string
	}{
		{
			name:           "nil error",
			err:            nil,
			expectedRollup: false,
		},
		{
			name:           "non mysql error",
			err:            errors.New("some error"),
			expectedRollup: false,
		},
		{
			name: "mysql error",
			err: &mysql.MySQLError{
				Number: 1062,
			},
			expectedRollup: true,
			expectedInfo:   "mysql error 1062",
		},
		{
			name: "wrapped mysql error",
			err: errors.Wrap(&mysql.MySQLError{
				Number: 1062,
			}, "wrapped"),
			expectedRollup: true,
			expectedInfo:   "mysql error 1062",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := RollupDBError(tt.err)
			if tt.expectedRollup {
				roller, ok := err.(exceptions.RollupInfoer)
				require.True(t, ok, "expected error to be a RollupInfoer")
				require.Equal(t, tt.expectedInfo, roller.RollupInfo())
			} else {
				require.Equal(t, tt.err, err)
			}
		})
	}
}

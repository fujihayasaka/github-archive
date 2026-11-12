package agent

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestNewJobID covers parsing logic in job.go ensuring correct extraction of owner & repo IDs
// and proper error handling for malformed identifiers.
func TestJobIDParsingTable(t *testing.T) {
	tests := []struct {
		name      string
		input     string
		wantOwner int64
		wantRepo  int64
		wantErr   error
	}{
		{
			name:      "simple valid id",
			input:     "1-2-someuuid",
			wantOwner: 1,
			wantRepo:  2,
		},
		{
			name:      "valid id with extra hyphens in tail",
			input:     "123-456-abc-def-ghi", // third segment preserves remaining hyphens due to SplitN(...,3)
			wantOwner: 123,
			wantRepo:  456,
		},
		{
			name:    "too few parts",
			input:   "123-456",
			wantErr: ErrInvalidJobIDFormat,
		},
		{
			name:    "non integer owner",
			input:   "abc-456-rest",
			wantErr: ErrInvalidJobIDOwner,
		},
		{
			name:    "non integer repo",
			input:   "123-xyz-rest",
			wantErr: ErrInvalidJobIDRepo,
		},
		{
			name:    "empty string",
			input:   "",
			wantErr: ErrInvalidJobIDFormat,
		},
		{
			name:    "leading dash (empty owner part)",
			input:   "-1-uuid", // splits to ["", "1", "uuid"]
			wantErr: ErrInvalidJobIDFormat,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := NewJobID(tc.input)
			if tc.wantErr != nil {
				require.Error(t, err)
				assert.ErrorIs(t, err, tc.wantErr)
				return
			}
			require.NoError(t, err)
			require.NotNil(t, got)
			assert.Equal(t, tc.wantOwner, got.Owner, "owner mismatch")
			assert.Equal(t, tc.wantRepo, got.Repo, "repo mismatch")
			assert.Equal(t, tc.input, got.Value, "value should equal original input")
		})
	}
}

func TestAgentNewJobID(t *testing.T) {
	t.Run("valid id", func(t *testing.T) {
		id, err := NewJobID("123-456-abc-def")
		require.NoError(t, err)
		require.Equal(t, int64(123), id.Owner)
		require.Equal(t, int64(456), id.Repo)
		require.Equal(t, "123-456-abc-def", id.Value)
	})
	t.Run("invalid format - too few parts", func(t *testing.T) {
		_, err := NewJobID("123-456")
		require.ErrorIs(t, err, ErrInvalidJobIDFormat)
	})
	t.Run("invalid format - non int owner", func(t *testing.T) {
		_, err := NewJobID("abc-456-rest")
		require.ErrorIs(t, err, ErrInvalidJobIDOwner)
	})
	t.Run("invalid format - non int repo", func(t *testing.T) {
		_, err := NewJobID("123-xyz-rest")
		require.ErrorIs(t, err, ErrInvalidJobIDRepo)
	})
}

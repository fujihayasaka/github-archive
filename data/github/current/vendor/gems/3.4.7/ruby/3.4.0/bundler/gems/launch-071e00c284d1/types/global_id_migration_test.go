// THIS FILE WILL BE DELETED WHEN THE GLOBAL ID MIGRATION IS COMPLETE
// Tracking issue: https://github.com/github/c2c-actions-experience/issues/6576

package types

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/utils/testutils"
)

func Test_NewGlobalID(t *testing.T) {
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	testCases := []struct {
		value       string
		logExpected bool
	}{
		{"", false},
		{"U_kgDOAAFjIg", false},
		{"MDQ6VXNlcjkwOTE0", true},
		{"InvalidValue", true},
	}

	for _, tc := range testCases {
		t.Run(tc.value, func(t *testing.T) {
			rlogger := testutils.NewRecordingLogger()
			log = rlogger.Logger

			gid := NewGlobalID(ctx, tc.value)

			// Verify creating a global id returns a value equal to a type conversion
			assert.Equal(t, gid, GlobalID(tc.value))
			assert.Equal(t, gid.String(), tc.value)

			// Verify legacy global ids are logged
			if tc.logExpected {
				assert.Contains(t, rlogger.String(), "wrong global id format")
			} else {
				assert.NotContains(t, rlogger.String(), "wrong global id format")
			}
		})
	}
}

func Test_GlobalID_UnmarshalJSON_Logging(t *testing.T) {
	testCases := []struct {
		json        string
		val         GlobalID
		logExpected bool
	}{
		{`{"Val":""}`, NilGlobalID, false},
		{`{"Val":null}`, NilGlobalID, false},
		{`{"Val":"U_kgDOAAFjIg"}`, GlobalID("U_kgDOAAFjIg"), false},
		{`{"Val":"MDQ6VXNlcjkwOTE0"}`, GlobalID("MDQ6VXNlcjkwOTE0"), true},
	}

	for _, tc := range testCases {
		t.Run(tc.val.String(), func(t *testing.T) {
			var data struct {
				Val GlobalID
			}

			rlogger := testutils.NewRecordingLogger()
			log = rlogger.Logger

			err := json.Unmarshal([]byte(tc.json), &data)
			require.NoError(t, err)
			assert.Equal(t, tc.val, data.Val, "Val, as decoded from %q", string(tc.json))

			// Verify legacy global ids are logged
			if tc.logExpected {
				assert.Contains(t, rlogger.String(), "wrong global id format")
			} else {
				assert.NotContains(t, rlogger.String(), "wrong global id format")
			}
		})
	}
}

package globalid

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestGlobalIdParseErrors(t *testing.T) {
	tests := map[string]struct {
		gid         string
		errorString string
	}{
		"invalid scheme": {
			gid:         "http://google.com",
			errorString: "invalid globalId scheme",
		},
		"invalid host": {
			gid:         "gid://user@/",
			errorString: "globalId scheme requires an app name",
		},
		"not enough paths": {
			gid:         "gid://git-hub/User",
			errorString: "globalId scheme requires a model_name and model_id",
		},
		"perfect": {
			gid:         "gid://git-hub/User/1",
			errorString: "",
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := Parse(test.gid)

			if test.errorString != "" {
				require.Error(t, err)
				assert.ErrorContains(t, err, test.errorString)
			}
		})
	}
}

func TestGlobalIdParse(t *testing.T) {
	tests := map[string]struct {
		gid      string
		expected *GlobalID
	}{
		"perfect": {
			gid: "gid://git-hub/User/1",
			expected: &GlobalID{
				App:       "git-hub",
				ModelName: "User",
				ModelID:   "1",
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			gid, err := Parse(test.gid)
			require.NoError(t, err)
			assert.Equal(t, test.expected, gid)
		})
	}
}

func TestGlobalIdString(t *testing.T) {
	tests := map[string]struct {
		gid      *GlobalID
		expected string
	}{
		"perfect": {
			gid: &GlobalID{
				App:       "git-hub",
				ModelName: "User",
				ModelID:   "1",
			},
			expected: "gid://git-hub/User/1",
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			assert.Equal(t, test.expected, test.gid.String())
		})
	}
}

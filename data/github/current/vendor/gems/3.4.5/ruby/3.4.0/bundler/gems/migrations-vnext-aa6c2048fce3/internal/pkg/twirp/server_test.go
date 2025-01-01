package twirp

import (
	"io"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_NewServer(t *testing.T) {
	tests := map[string]struct {
		opts           []ServerOption
		wantsErr       bool
		wantsErrSubstr string
	}{
		"should return an error if no manager": {
			opts: []ServerOption{
				WithManager(nil),
				WithStatter(stats.NewClient(io.Discard, time.Second, "test")),
				WithHMACKeys([]string{"key1", "key2"}),
			},
			wantsErr:       true,
			wantsErrSubstr: "invalid twirp server configuration",
		},
		"should return an error if no HMAC keys": {
			opts: []ServerOption{
				WithManager(dag.NewManager(nil, nil, log.NewNullLogger())),
				WithStatter(stats.NewClient(io.Discard, time.Second, "test")),
				WithHMACKeys([]string{}),
			},
			wantsErr:       true,
			wantsErrSubstr: "invalid twirp server configuration",
		},
		"should not return an error when properly configured": {
			opts: []ServerOption{
				WithManager(dag.NewManager(nil, nil, log.NewNullLogger())),
				WithStatter(stats.NewClient(io.Discard, time.Second, "test")),
				WithHMACKeys([]string{"key1", "key2"}),
			},
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			srv, err := NewServer(test.opts...)

			require.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			}
			assert.NotNil(t, srv.logger) // The rest of these checks assert defaults
			assert.NotNil(t, srv.mux)
		})
	}
}

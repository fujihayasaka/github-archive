package mvnd

import (
	"io"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/stretchr/testify/assert"
)

func Test_New(t *testing.T) {
	tests := map[string]struct {
		forceValidationError bool
		wantsErr             bool
		wantsErrSubstr       string
	}{
		"should return an error if the instance is misconfigured": {
			forceValidationError: true,
			wantsErr:             true,
			wantsErrSubstr:       "invalid configuration provided",
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			statter := stats.NewClient(io.Discard, time.Second, "test")

			opts := []Option{
				WithManager(dag.NewManager(dag.NewMemoryDAG(), dag.NewMemoryObjectStore(), log.NewNullLogger())),
				WithStatter(statter),
				WithHMACKeys([]string{"key1", "key2"}),
			}
			if test.forceValidationError {
				opts = append(opts, WithListenAddr("invalid-addr"))
			}

			mvnd, err := New(opts...)

			assert.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr && (err != nil) {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			} else {
				assert.Same(t, statter, mvnd.statter) // Checks that options were applied
				assert.NotNil(t, mvnd.httpServer)     // The rest of these checks assert defaults
				assert.NotEmpty(t, mvnd.listenAddr)
				assert.NotNil(t, mvnd.logger)
			}
		})
	}
}

func Test_validate(t *testing.T) {
	tests := map[string]struct {
		hasListenAddr  string
		wantsErr       bool
		wantsErrSubstr string
	}{
		"should return an error when an invalid listen address is configured": {
			hasListenAddr:  "will-error",
			wantsErr:       true,
			wantsErrSubstr: "invalid listen address",
		},
		"should return an error when no HMAC keys are configured": {
			hasListenAddr:  ":80",
			wantsErr:       true,
			wantsErrSubstr: "must have at least one HMAC key",
		},
	}

	for name, test := range tests {
		t.Run(name, func(t *testing.T) {
			m := &Mvnd{
				listenAddr: test.hasListenAddr,
			}

			err := m.validate()
			assert.Equal(t, test.wantsErr, err != nil)
			if test.wantsErr && (err != nil) {
				assert.Contains(t, err.Error(), test.wantsErrSubstr)
			}
		})
	}
}

package twirp

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/stretchr/testify/assert"
)

func Test_WithLogger(t *testing.T) {
	s := &Server{}
	logger := log.NewNullLogger()
	WithLogger(logger)(s)

	assert.Same(t, logger, s.logger)
}

func Test_WithManager(t *testing.T) {
	s := &Server{}
	manager := dag.NewManager(nil, nil, log.NewNullLogger())
	WithManager(manager)(s)

	assert.Same(t, manager, s.manager)
}

func Test_WithStatter(t *testing.T) {
	s := &Server{}
	statter := stats.NullStatter
	WithStatter(statter)(s)

	assert.Same(t, statter, s.statter)
}

func Test_WithHMACKeys(t *testing.T) {
	s := &Server{}
	keys := []string{"key1", "key2"}
	WithHMACKeys(keys)(s)

	assert.Equal(t, keys, s.hmacKeys)
}

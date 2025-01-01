package mvnd

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/stretchr/testify/assert"
)

func Test_WithListenAddr(t *testing.T) {
	m := &Mvnd{}
	listenAddr := "localhost:1234"
	WithListenAddr(listenAddr)(m)

	assert.Equal(t, listenAddr, m.listenAddr)
}

func Test_WithLogger(t *testing.T) {
	m := &Mvnd{}
	logger := log.NewNullLogger()
	WithLogger(logger)(m)

	assert.Same(t, logger, m.logger)
}

func Test_WithManager(t *testing.T) {
	m := &Mvnd{}
	manager := dag.NewManager(nil, nil, log.NewNullLogger())
	WithManager(manager)(m)

	assert.Same(t, manager, m.manager)
}

func Test_WithStatter(t *testing.T) {
	m := &Mvnd{}
	statter := stats.NullStatter
	WithStatter(statter)(m)

	assert.Same(t, statter, m.statter)
}

func Test_WithHMACKeys(t *testing.T) {
	m := &Mvnd{}
	keys := []string{"key1", "key2"}
	WithHMACKeys(keys)(m)

	assert.Equal(t, keys, m.hmacKeys)
}

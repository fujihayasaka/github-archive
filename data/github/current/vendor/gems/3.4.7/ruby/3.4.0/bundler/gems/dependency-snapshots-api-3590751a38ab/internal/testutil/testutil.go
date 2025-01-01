package testutil

import (
	"database/sql/driver"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/stretchr/testify/require"
)

// Matches any time.Time instance in a sqlmock arguments list
type AnyTime struct{}

// Match satisfies sqlmock.Argument interface
func (a AnyTime) Match(v driver.Value) bool {
	_, ok := v.(time.Time)
	return ok
}

// Matches any time later than the given one
type AfterTime struct {
	time.Time
}

// Match satisfies sqlmock.Argument interface
func (a AfterTime) Match(v driver.Value) bool {
	t, ok := v.(time.Time)
	return ok && t.After(a.Time)
}

func MatchTimeAfter(t time.Time) sqlmock.Argument {
	return AfterTime{t}
}

func CreateTestConfig(t *testing.T) *config.Config {
	t.Helper()

	cfg, err := config.Load("test_run_fake_build_commit")
	require.NoError(t, err)

	cfg.DB = "dependency_snapshots_test"
	return cfg
}

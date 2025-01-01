package main

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

const (
	fixtureDir = "testdata"
)

// The old test was checking alert creation. Since we are using a
// common processing step, we should check that we do arg parsing and
// other activities correctly, instead
func TestParseAndStore(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)

	logger, err := cfg.NewLogger()
	require.NoError(t, err)

	ctx := context.Background()
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)

	sarifPath := filepath.Join(fixtureDir, "example.sarif")
	now := time.Now()

	args := Args{
		repoID:       1,
		ownerID:      1,
		commit:       "beef",
		ref:          "main",
		analysisName: "codeQL",
		checkoutURI:  "file://",
		env:          "{\"os\" : \"linux\"}",
		runID:        71,
		startTime:    &now,
		paths:        []string{sarifPath},
	}

	err = parseAndStore(ctx, logger, stats.NullStatter, cfg, db, &args)
	require.NoError(t, err)

	dbtest.RequireCount(t, 2, db.Model(&ts.LogicalAlert{}))

	actual := &ts.LogicalAlert{}
	require.NoError(t, db.First(actual).Error)
	require.Equal(t, "main.js", actual.FilePath)

}

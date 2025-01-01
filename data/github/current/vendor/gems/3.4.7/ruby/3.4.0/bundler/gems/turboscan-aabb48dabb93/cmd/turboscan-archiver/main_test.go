package main

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestRealMain(t *testing.T) {
	require.NoError(t, realMain(&arguments{
		dryRun: true,
	}))
}

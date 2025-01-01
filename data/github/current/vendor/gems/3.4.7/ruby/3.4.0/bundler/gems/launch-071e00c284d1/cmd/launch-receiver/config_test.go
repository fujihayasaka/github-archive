package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestConfig_Validate(t *testing.T) {
	config := Config{
		ActionRunnerSecret: "secret",
	}

	t.Run("passes", func(tt *testing.T) {
		err := config.Validate()
		require.NoError(tt, err)
	})

	t.Run("ActionRunnerSecret missing", func(tt *testing.T) {
		badConfig := config
		badConfig.ActionRunnerSecret = ""
		err := badConfig.Validate()
		assert.EqualError(tt, err, "ACTION_RUNNER_SECRET can not be empty")
	})
}

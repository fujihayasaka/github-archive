package config_test

import (
	"context"
	"fmt"
	"os"
	"regexp"
	"testing"

	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/ts/config"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

func TestLoad(t *testing.T) {
	// Test defaults
	cfg, err := config.Load()
	require.NoError(t, err)
	require.Equal(t, "development", cfg.Environment)
	require.Equal(t, "", cfg.HMACKey)
	require.Equal(t, "", cfg.InsightsHMACKey)
	require.Equal(t, "", cfg.DependabotHMACKey)
	require.Len(t, cfg.ValidHMACs(), 0)
	require.Equal(t, int64(419430400), int64(cfg.MaxSarifSize))
}

type nonStackTraceError string

func (s nonStackTraceError) Error() string {
	return string(s)
}

type stacktraceError struct{}

func (s *stacktraceError) StackTrace() errors.StackTrace {
	return []errors.Frame{}
}

func (s *stacktraceError) Error() string {
	return "stacktraceError"
}

func TestRollupInfoFunc(t *testing.T) {
	t.Run("Has no line numbers", func(t *testing.T) {
		err := errors.New("test error")
		val, ok := config.RollupInfoFunc(err)
		require.True(t, ok)
		require.NotRegexp(t, regexp.MustCompile(`:\d+`), val)
	})
	t.Run("Workaround to deal with MySQL timeouts", func(t *testing.T) {
		err := nonStackTraceError("Error 1317 (70100): target: turboscan_ks.0.primary: vttablet: rpc error: code = Canceled desc = (errno 2013) due to context deadline exceeded, elapsed time: 1.806469277s, killing query ID 2404858 (CallerID: turboscan_rw)")
		val, ok := config.RollupInfoFunc(err)
		require.True(t, ok)
		require.Equal(t, "query execution was interrupted", val)
	})
	t.Run("handles a stacktracer", func(t *testing.T) {
		err := stacktraceError{}
		_, ok := config.RollupInfoFunc(&err)
		require.True(t, ok)
	})
	t.Run("handles a twirp io error", func(t *testing.T) {
		msg := fmt.Sprintf("failed to write response, %d of %d bytes written: %s", 100, 1000, os.ErrDeadlineExceeded.Error())
		twerr := twirp.NewError(twirp.Unknown, msg)
		m, ok := config.RollupInfoFunc(twerr)
		require.True(t, ok)
		require.Equal(t, "twirp error unknown: failed to write response", m)
	})
	t.Run("rolls up context cancellations", func(t *testing.T) {
		err := errors.Wrap(context.Canceled, "context canceled")
		val, ok := config.RollupInfoFunc(err)
		require.True(t, ok)
		require.Equal(t, "context canceled", val)
	})
}

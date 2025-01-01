package twirp

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/dependencies"
	"github.com/stretchr/testify/require"
)

// newTestServer creates a new test server with the given dependencies configuration.
// Has optional configuration options.
// To inject a custom dependencies configuration, use the withDependencies option.
func newTestServer(t *testing.T, configOpts ...func(*opts)) *Server {
	t.Helper()

	opts := &opts{}
	for _, opt := range configOpts {
		opt(opts)
	}

	app, err := application.NewNullApplication(&application.NullConfig{DependenciesConfig: opts.DependenciesConfig}, log.NewNullLogger())
	require.NoError(t, err)
	t.Cleanup(func() {
		err = app.Close()
		if err != nil {
			t.Errorf("failed to close app : %v", err)
		}
	})

	return &Server{
		app: app,
	}
}

type opts struct {
	DependenciesConfig dependencies.NullConfig
}

func withDependencies(dpConfig dependencies.NullConfig) func(*opts) {
	return func(o *opts) {
		o.DependenciesConfig = dpConfig
	}
}

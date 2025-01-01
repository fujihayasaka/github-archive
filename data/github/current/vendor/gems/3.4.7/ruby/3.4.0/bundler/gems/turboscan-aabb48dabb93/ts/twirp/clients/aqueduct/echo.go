package aqueduct

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
)

// EchoJob is a test job that logs a message.
// It can be used to check that the system is configured correctly and there is at least one worker.
type EchoJob struct {
	Message string
}

func (j EchoJob) GetRepositoryID() *ts.RepositoryEID {
	return nil
}

func (j EchoJob) Name() string {
	return "EchoJob"
}

func (j EchoJob) Queue() string {
	return "turboscan-echo"
}

func (j EchoJob) Perform(ctx context.Context, _ *TSServices) error {
	appctx.Logger(ctx).Info("Payload", kvp.String("gh.turboscan.payload", j.Message))
	return nil
}

func (j EchoJob) GetRetryBackoffFunc() RetryBackoffFunc {
	return DefaultRetryBackoffFunc
}

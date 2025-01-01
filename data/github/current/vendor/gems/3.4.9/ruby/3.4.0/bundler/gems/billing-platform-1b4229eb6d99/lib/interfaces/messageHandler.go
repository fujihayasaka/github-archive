package interfaces

import (
	"context"

	"github.com/github/github-telemetry-go/log"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
)

type MessageHandler interface {
	ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error
	ReceiveQueueName() string
	GetProcessJobError() error
}

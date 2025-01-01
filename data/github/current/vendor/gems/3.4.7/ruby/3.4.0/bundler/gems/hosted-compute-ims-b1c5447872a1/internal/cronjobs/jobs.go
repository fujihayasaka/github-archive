package cronjobs

import (
	"context"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/azure"
	"github.com/github/hosted-compute-ims/internal/resources"
	"github.com/github/hosted-compute-ims/internal/store"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_runner"
)

type Job interface {
	Perform(ctx context.Context) error
	GetName() string
}

type BaseJob struct {
	ImagesStore  store.IImagesStore
	AzureClient  azure.IAzureClient
	Manager      resources.IManager
	RunnerClient vssf_runner.Client
	Logger       *telemetry.ReportingLogger
}

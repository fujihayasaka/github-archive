package cronjobs

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_azure"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_manager"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	mocks_runner "github.com/github/hosted-compute-ims/gen/mocks/mocks_vssf_runner"
	"go.uber.org/mock/gomock"
)

var (
	mockRunnerClient *mocks_runner.MockClient
	mockImagesStore  *mocks_store.MockIImagesStore
	mockAzureClient  *mocks_azure.MockIAzureClient
	mockManager      *mocks_manager.MockIManager
)

func setup(t *testing.T) (*gomock.Controller, BaseJob) {
	ctrl := gomock.NewController(t)
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	mockRunnerClient = mocks_runner.NewMockClient(ctrl)
	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockAzureClient = mocks_azure.NewMockIAzureClient(ctrl)
	mockManager = mocks_manager.NewMockIManager(ctrl)

	baseJob := BaseJob{
		ImagesStore:  mockImagesStore,
		RunnerClient: mockRunnerClient,
		AzureClient:  mockAzureClient,
		Manager:      mockManager,
		Logger:       logger,
	}

	return ctrl, baseJob
}

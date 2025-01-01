package twirp

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_manager"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_store"
	"github.com/github/hosted-compute-ims/gen/mocks/mocks_worker"
	"go.uber.org/mock/gomock"
)

var (
	mockImagesStore       *mocks_store.MockIImagesStore
	mockWorkerQueueClient *mocks_worker.MockIWorkerQueueClient
	mockManager           *mocks_manager.MockIManager
)

func setupImagesApiHandler(t *testing.T) (*gomock.Controller, *ImagesApiHandler) {
	ctrl := gomock.NewController(t)
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockWorkerQueueClient = mocks_worker.NewMockIWorkerQueueClient(ctrl)

	return ctrl, &ImagesApiHandler{
		baseApiHandler{
			logger:            logger,
			imageStore:        mockImagesStore,
			workerQueueClient: mockWorkerQueueClient,
		},
	}
}

func setupImagesAdminApiHandler(t *testing.T) (*gomock.Controller, *ImagesAdminApiHandler) {
	ctrl := gomock.NewController(t)
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockWorkerQueueClient = mocks_worker.NewMockIWorkerQueueClient(ctrl)

	return ctrl, &ImagesAdminApiHandler{
		baseApiHandler{
			logger:            logger,
			imageStore:        mockImagesStore,
			workerQueueClient: mockWorkerQueueClient,
		},
	}
}

func setupInternalImagesApiHandler(t *testing.T) (*gomock.Controller, *InternalImagesApiHandler) {
	ctrl := gomock.NewController(t)
	logger := telemetry.NewReportingLogger(log.NewNullLogger(), exceptions.NullReporter, stats.NullStatter)

	mockImagesStore = mocks_store.NewMockIImagesStore(ctrl)
	mockWorkerQueueClient = mocks_worker.NewMockIWorkerQueueClient(ctrl)
	mockManager = mocks_manager.NewMockIManager(ctrl)

	return ctrl, &InternalImagesApiHandler{
		baseApiHandler{
			logger:            logger,
			imageStore:        mockImagesStore,
			manager:           mockManager,
			workerQueueClient: mockWorkerQueueClient,
		},
	}
}

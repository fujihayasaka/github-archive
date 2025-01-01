package jobs_test

import (
	"context"
	"database/sql/driver"
	"testing"
	"time"

	"github.com/aws/smithy-go/ptr"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/delivery_processor"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestProcessDelivery(t *testing.T) {
	db := dbtest.RequireConnectionWithoutTransaction(t)
	deliveryService := delivery.NewService(db)
	repoID := ts.RepositoryEID(123)
	job := jobs.ProcessDelivery{
		RepoID: repoID,
	}
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	pub := mocks.NewMockAnalysisPublisher(mockCtrl)
	p := mocks.NewMockProcessor(mockCtrl)
	s := mocks.NewMockStatusService(mockCtrl)
	services := &aqueduct.TSServices{
		DeliveryProcessor: delivery_processor.NewDeliveryProcessor(deliveryService, p, pub, s, 10*time.Second),
		Aqueduct:          &aqueduct.AqueductMock{},
	}

	require.NoError(t, job.Perform(ctx, services))
}

func TestProcessDeliveryMaxDeliveries(t *testing.T) {
	repoID := ts.RepositoryEID(123)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	deliveryService := mocks.NewMockDeliveryService(mockCtrl)
	pub := mocks.NewMockAnalysisPublisher(mockCtrl)
	p := mocks.NewMockProcessor(mockCtrl)
	s := mocks.NewMockStatusService(mockCtrl)
	aqMock := &aqueduct.AqueductMock{}
	services := &aqueduct.TSServices{
		// set the processing deadline to be zero so that we automatically give up control of the job
		DeliveryProcessor: delivery_processor.NewDeliveryProcessor(deliveryService, p, pub, s, 0),
		Aqueduct:          aqMock,
	}

	d := &ts.Delivery{
		RepositoryID: repoID,
		SarifPath:    "example.sarif",
		CommitOid:    SHA40a,
		Ref:          []byte("refs/heads/branch"),
		AnalysisKey:  "woot",
		Environment:  ts.AnalysisEnv{},
		CheckoutURI:  "",
	}

	deliveryService.EXPECT().NextDelivery(gomock.Any(), repoID).Return(d, nil)

	job := jobs.ProcessDelivery{
		RepoID: repoID,
	}

	require.NoError(t, job.Perform(ctx, services))
	require.Equal(t, 1, len(aqMock.EnqueuedJobs()))

	job = jobs.ProcessDelivery{
		RepoID: repoID,
	}

	deliveryService.EXPECT().NextDelivery(gomock.Any(), repoID).Return(d, nil)

	require.NoError(t, job.Perform(ctx, services))
	// Ensure we have requeued another job because we hit max deliveries processed again
	require.Equal(t, 2, len(aqMock.EnqueuedJobs()))
}

func TestProcessDeliveryRetry(t *testing.T) {
	repoID := ts.RepositoryEID(123)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	db := dbtest.RequireConnection(t)

	deliveryService := delivery.NewService(db)
	pub := mocks.NewMockAnalysisPublisher(mockCtrl)
	p := mocks.NewMockProcessor(mockCtrl)
	s := mocks.NewMockStatusService(mockCtrl)
	aqMock := &aqueduct.AqueductMock{}
	services := &aqueduct.TSServices{
		// set the processing deadline to be zero so that we automatically give up control of the job
		DeliveryProcessor: delivery_processor.NewDeliveryProcessor(deliveryService, p, pub, s, 10*time.Second),
		Aqueduct:          aqMock,
	}

	d := &ts.Delivery{
		RepositoryID:        repoID,
		SarifPath:           "example.sarif",
		CommitOid:           SHA40a,
		Ref:                 []byte("refs/heads/branch"),
		AnalysisKey:         "woot",
		Environment:         ts.AnalysisEnv{},
		CheckoutURI:         "",
		ProcessingStartedAt: ptr.Time(time.Now()),
	}

	require.NoError(t, deliveryService.CreateDelivery(ctx, d))

	p.EXPECT().ProcessNewDelivery(gomock.Any(), gomock.Any()).Return(nil, driver.ErrBadConn)

	pub.EXPECT().FailedAnalysis(gomock.Any(), gomock.Any()).Times(0)

	job := jobs.ProcessDelivery{
		RepoID:  repoID,
		Attempt: 0,
	}

	jobErr := job.Perform(ctx, services)

	require.ErrorIs(t, jobErr, driver.ErrBadConn)
	require.ErrorIs(t, jobErr, &delivery_processor.ErrTryAgainLater{})
}

func TestProcessDeliveryMaxRetries(t *testing.T) {
	repoID := ts.RepositoryEID(123)
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	db := dbtest.RequireConnection(t)

	deliveryService := delivery.NewService(db)
	pub := mocks.NewMockAnalysisPublisher(mockCtrl)
	p := mocks.NewMockProcessor(mockCtrl)
	s := mocks.NewMockStatusService(mockCtrl)
	aqMock := &aqueduct.AqueductMock{}
	services := &aqueduct.TSServices{
		// set the processing deadline to be zero so that we automatically give up control of the job
		DeliveryProcessor: delivery_processor.NewDeliveryProcessor(deliveryService, p, pub, s, 10*time.Second),
		Aqueduct:          aqMock,
	}

	d := &ts.Delivery{
		RepositoryID:        repoID,
		SarifPath:           "example.sarif",
		CommitOid:           SHA40a,
		Ref:                 []byte("refs/heads/branch"),
		AnalysisKey:         "woot",
		Environment:         ts.AnalysisEnv{},
		CheckoutURI:         "",
		ProcessingStartedAt: ptr.Time(time.Now()),
	}

	require.NoError(t, deliveryService.CreateDelivery(ctx, d))

	p.EXPECT().ProcessNewDelivery(gomock.Any(), gomock.Any()).Return(nil, driver.ErrBadConn)

	pub.EXPECT().FailedAnalysis(gomock.Any(), gomock.Any())

	job := jobs.ProcessDelivery{
		RepoID:  repoID,
		Attempt: 100,
	}

	jobErr := job.Perform(ctx, services)

	require.NoError(t, jobErr, driver.ErrBadConn)
}

const SHA40a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

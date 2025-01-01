package worker

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/github/hosted-compute-ims/gen/mocks/mocks_promotion"
	"github.com/github/hosted-compute-ims/internal/promotion"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
	"github.com/github/hosted-compute-ims/internal/worker/queue"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

var mockPromotion *mocks_promotion.MockIImagePromotionClient

func setup(ctx context.Context, t *testing.T) (*gomock.Controller, *WorkerPool, queue.IWorkerQueueClient) {
	ctrl := gomock.NewController(t)
	mockPromotion = mocks_promotion.NewMockIImagePromotionClient(ctrl)

	aqueductCfg := getTestAqueductConfig(t)

	workerQueueClient, err := queue.NewWorkerQueueClient(ctx, &aqueductCfg)
	require.NoError(t, err)

	workerPoolCfg := &Config{
		Aqueduct:                 aqueductCfg,
		RetriesBaseBackoff:       time.Duration(-1),
		RetriesExponentialFactor: 1,
		JobReceiveTimeout:        time.Duration(1),
	}
	workerPool, err := NewWorkerPool(ctx, workerPoolCfg, mockPromotion)
	require.NoError(t, err)

	return ctrl, workerPool, workerQueueClient
}

func getTestAqueductConfig(t *testing.T) aqueduct.Config {
	aqueductCfg := aqueduct.Config{}

	err := aqueductCfg.Load()
	require.NoError(t, err)

	aqueductAddress, err := utils.GetMinikubeIp()
	require.NoError(t, err)

	// override aqueduct address to use development instance
	aqueductCfg.Addr = fmt.Sprintf("http://%s:28141", aqueductAddress)
	// override aqueduct app name to not mix data with development
	aqueductCfg.AppName = fmt.Sprintf("test-%d", time.Now().Unix())

	return aqueductCfg
}

func assertAllQueuesAreEmpty(ctx context.Context, t *testing.T, workerPool *WorkerPool) {
	for _, queueName := range workerPool.allQueueNames {
		depth, err := workerPool.aqueductClient.QueueDepth(ctx, workerPool.config.Aqueduct.AppName, queueName)
		require.NoError(t, err)
		require.Equal(t, int64(0), depth, "queue %s is not empty", queueName)
	}
}

func TestWorkerJobs(t *testing.T) {
	ctx := context.Background()
	imageVersionId := uint64(1)
	sourceVhdUrl := "https://source.blob.core.windows.net/vhds/source.vhd"
	retryableError := promotion.PromotionError{Err: fmt.Errorf("writing data"), UserErrorDetails: "writing data", NonRetryable: false}
	nonRetryableError := promotion.PromotionError{Err: fmt.Errorf("test"), UserErrorDetails: "test", NonRetryable: true}

	t.Run("ProvisionImageVersion passes on first attempt", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().ProvisionImageVersion(gomock.Any(), imageVersionId, sourceVhdUrl, "").Return(nil)

		err = workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, sourceVhdUrl, "")
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionImageVersion passes on third attempt", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		gomock.InOrder(
			mockPromotion.EXPECT().ProvisionImageVersion(gomock.Any(), imageVersionId, sourceVhdUrl, "").Times(2).Return(&retryableError),
			mockPromotion.EXPECT().ProvisionImageVersion(gomock.Any(), imageVersionId, sourceVhdUrl, "").Return(nil),
		)

		err = workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, sourceVhdUrl, "")
		require.NoError(t, err)

		for i := 0; i < 3; i++ {
			err = worker.ProcessJob(ctx)
			require.NoError(t, err)
		}

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionImageVersion fails after max retries", func(t *testing.T) {
		maxRetries := QueueToJobMapping[queue.QueueName_ProvisionImageVersion].maxRetriesCount

		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		gomock.InOrder(
			mockPromotion.EXPECT().ProvisionImageVersion(gomock.Any(), imageVersionId, sourceVhdUrl, "").Times(maxRetries).Return(&retryableError),
			mockPromotion.EXPECT().ProvisionImageVersionFailedAfterMaxRetries(gomock.Any(), imageVersionId, gomock.Any()),
		)

		err = workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, sourceVhdUrl, "")
		require.NoError(t, err)

		for i := 0; i < maxRetries; i++ {
			err = worker.ProcessJob(ctx)
			if err != nil {
				require.IsType(t, &promotion.PromotionError{}, err)
			}
		}

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionImageVersion stops after first attempt on non-retryable error", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		gomock.InOrder(
			mockPromotion.EXPECT().ProvisionImageVersion(gomock.Any(), imageVersionId, sourceVhdUrl, "").Return(&nonRetryableError),
			mockPromotion.EXPECT().ProvisionImageVersionFailedAfterMaxRetries(gomock.Any(), imageVersionId, gomock.Any()),
		)

		err = workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, sourceVhdUrl, "")
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("DeleteImageVersionJob passes on first attempt", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().DeleteImageVersion(gomock.Any(), imageVersionId).Return(nil)

		err = workerQueueClient.QueueDeleteImageVersionJob(ctx, imageVersionId)
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("DeleteImageVersionJob passes on third attempt", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		gomock.InOrder(
			mockPromotion.EXPECT().DeleteImageVersion(gomock.Any(), imageVersionId).Times(2).Return(&retryableError),
			mockPromotion.EXPECT().DeleteImageVersion(gomock.Any(), imageVersionId).Return(nil),
		)

		err = workerQueueClient.QueueDeleteImageVersionJob(ctx, imageVersionId)
		require.NoError(t, err)

		for i := 0; i < 3; i++ {
			err = worker.ProcessJob(ctx)
			require.NoError(t, err)
		}

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("DeleteImageVersionJob fails after max retries", func(t *testing.T) {
		maxRetries := QueueToJobMapping[queue.QueueName_DeleteImageVersion].maxRetriesCount

		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().DeleteImageVersion(gomock.Any(), imageVersionId).Times(maxRetries).Return(&retryableError)

		err = workerQueueClient.QueueDeleteImageVersionJob(ctx, imageVersionId)
		require.NoError(t, err)

		for i := 0; i < maxRetries; i++ {
			err = worker.ProcessJob(ctx)
			require.NoError(t, err)
		}

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("DeleteImageVersionJob stops after first attempt on non-retryable error", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().DeleteImageVersion(gomock.Any(), imageVersionId).Return(&nonRetryableError)

		err = workerQueueClient.QueueDeleteImageVersionJob(ctx, imageVersionId)
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionCleanupJob passes on first attempt", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().CleanupImageVersionResources(gomock.Any(), imageVersionId).Return(nil)

		err = workerQueueClient.QueueProvisionCleanupJob(ctx, imageVersionId)
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionCleanupJob passes on second attempt", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		gomock.InOrder(
			mockPromotion.EXPECT().CleanupImageVersionResources(gomock.Any(), imageVersionId).Times(1).Return(&retryableError),
			mockPromotion.EXPECT().CleanupImageVersionResources(gomock.Any(), imageVersionId).Return(nil),
		)

		err = workerQueueClient.QueueProvisionCleanupJob(ctx, imageVersionId)
		require.NoError(t, err)

		for i := 0; i < 2; i++ {
			err = worker.ProcessJob(ctx)
			require.NoError(t, err)
		}

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionCleanupJob fails after max retries", func(t *testing.T) {
		maxRetries := QueueToJobMapping[queue.QueueName_ProvisionCleanup].maxRetriesCount

		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().CleanupImageVersionResources(gomock.Any(), imageVersionId).Times(maxRetries).Return(&retryableError)

		err = workerQueueClient.QueueProvisionCleanupJob(ctx, imageVersionId)
		require.NoError(t, err)

		for i := 0; i < maxRetries; i++ {
			err = worker.ProcessJob(ctx)
			require.NoError(t, err)
		}

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("ProvisionCleanupJob stops after first attempt on non-retryable error", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		mockPromotion.EXPECT().CleanupImageVersionResources(gomock.Any(), imageVersionId).Return(&nonRetryableError)

		err = workerQueueClient.QueueProvisionCleanupJob(ctx, imageVersionId)
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})

	t.Run("Skip retrying of jobs failed due to shared dev subscription", func(t *testing.T) {
		ctrl, workerPool, workerQueueClient := setup(ctx, t)
		defer ctrl.Finish()

		worker, err := workerPool.NewWorker()
		require.NoError(t, err)

		innerError := fmt.Errorf("failed to provision: %w", errors.New(utils.SharedDevImagesErrorMessage))
		promotionError := &promotion.PromotionError{Err: innerError, UserErrorDetails: "test", NonRetryable: false}

		gomock.InOrder(
			mockPromotion.EXPECT().ProvisionImageVersion(gomock.Any(), imageVersionId, sourceVhdUrl, "").Return(promotionError),
			mockPromotion.EXPECT().ProvisionImageVersionFailedAfterMaxRetries(gomock.Any(), imageVersionId, gomock.Any()),
		)

		err = workerQueueClient.QueueProvisionImageVersionJob(ctx, imageVersionId, sourceVhdUrl, "")
		require.NoError(t, err)

		err = worker.ProcessJob(ctx)
		require.NoError(t, err)

		assertAllQueuesAreEmpty(ctx, t, workerPool)
	})
}

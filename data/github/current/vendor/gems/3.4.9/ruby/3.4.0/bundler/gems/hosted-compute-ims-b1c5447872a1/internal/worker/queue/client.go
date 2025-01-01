package queue

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/hosted-compute-core/cryptography"
	"github.com/github/hosted-compute-ims/internal/worker/aqueduct"
)

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_worker/mock_queue.go -package mocks_worker
type IWorkerQueueClient interface {
	QueueProvisionImageVersionJob(ctx context.Context, imageVersionId uint64, sourceVhdUrl string) error
	QueueDeleteImageVersionJob(ctx context.Context, imageVersionId uint64) error
	QueueProvisionCleanupJob(ctx context.Context, imageVersionId uint64) error
}

type WorkerQueueClient struct {
	aqueductClient     aqueduct.Client
	aqueductAppName    string
	cryptographyClient *cryptography.CryptoClient
}

func NewWorkerQueueClient(cfg *aqueduct.Config) (*WorkerQueueClient, error) {
	aqueductClient, err := aqueduct.NewAqueductClient(cfg)
	if err != nil {
		return nil, fmt.Errorf("failed to create aqueduct client: %w", err)
	}

	cryptoClient := cryptography.NewCryptoClient(cfg.EncryptionKeyList)

	return &WorkerQueueClient{
		aqueductClient:     aqueductClient,
		aqueductAppName:    cfg.AppName,
		cryptographyClient: cryptoClient,
	}, nil
}

func (q *WorkerQueueClient) QueueProvisionImageVersionJob(ctx context.Context, imageVersionId uint64, sourceVhdUrl string) error {
	encryptedVhdUrl, salt, err := q.encryptString(sourceVhdUrl)
	if err != nil {
		return fmt.Errorf("failed to encrypt source vhd url: %w", err)
	}

	jobPayload := ProvisionImageVersionJobPayload{
		ImageVersionId:      imageVersionId,
		SourceVhdUrlEncoded: encryptedVhdUrl,
		SourceVhdUrlSalt:    salt,
	}

	jobPayloadJson, err := json.Marshal(jobPayload)
	if err != nil {
		return fmt.Errorf("failed to marshal job payload: %w", err)
	}

	job := aqueduct.Job{App: q.aqueductAppName, Queue: QueueName_ProvisionImageVersion, Payload: jobPayloadJson}
	if _, err = q.aqueductClient.Send(ctx, job); err != nil {
		return fmt.Errorf("failed to send job to aqueduct: %w", err)
	}

	return nil
}

func (q *WorkerQueueClient) QueueDeleteImageVersionJob(ctx context.Context, imageVersionId uint64) error {
	jobPayload := DeleteImageVersionJobPayload{
		ImageVersionId: imageVersionId,
	}

	jobPayloadJson, err := json.Marshal(jobPayload)
	if err != nil {
		return fmt.Errorf("failed to marshal job payload: %w", err)
	}

	job := aqueduct.Job{App: q.aqueductAppName, Queue: QueueName_DeleteImageVersion, Payload: jobPayloadJson}
	if _, err = q.aqueductClient.Send(ctx, job); err != nil {
		return fmt.Errorf("failed to send job to aqueduct: %w", err)
	}

	return nil
}

func (q *WorkerQueueClient) QueueProvisionCleanupJob(ctx context.Context, imageVersionId uint64) error {
	jobPayload := ProvisionCleanupJobPayload{
		ImageVersionId: imageVersionId,
	}

	jobPayloadJson, err := json.Marshal(jobPayload)
	if err != nil {
		return fmt.Errorf("failed to marshal job payload: %w", err)
	}

	job := aqueduct.Job{App: q.aqueductAppName, Queue: QueueName_ProvisionCleanup, Payload: jobPayloadJson}
	if _, err = q.aqueductClient.Send(ctx, job); err != nil {
		return fmt.Errorf("failed to send job to aqueduct: %w", err)
	}

	return nil
}

func (q *WorkerQueueClient) encryptString(str string) ([]byte, []byte, error) {
	encryptedString, salt, err := q.cryptographyClient.Encrypt([]byte(str))
	if err != nil {
		return nil, nil, fmt.Errorf("failed to encrypt URL: %w", err)
	}

	return encryptedString, salt, nil
}

package launchblob

import (
	"context"
	"crypto/sha256"
	"encoding/binary"
	"errors"
	"fmt"

	"github.com/github/go-blob"
	"github.com/github/go-blob/sharder"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/payloads"
	"github.com/github/launch/types"
)

const version = 1

var ErrPayloadMetadataNotFound = errors.New("payload not found")

type payloadStoreBlob struct {
	blobClient            blob.Client
	sharder               *sharder.Sharder
	accountPrefix         string
	accountsCount         int
	container             string
	logger                logger.Logger
	stats                 statter.Statter
	payloadsMetadataStore deployer.PayloadMetadataRepository
}

func NewPayloadStore(bc blob.Client, accountIDs []int, accountsPrefix string, accountsCount int, container string, log logger.Logger, stats statter.Statter, payloadsMetadataStore deployer.PayloadMetadataRepository) (payloads.Store, error) {
	shard, err := sharder.New(accountIDs, accountsPrefix)
	if err != nil {
		return nil, err
	}

	return &payloadStoreBlob{
		blobClient:            bc,
		sharder:               shard,
		accountPrefix:         accountsPrefix,
		accountsCount:         accountsCount,
		container:             container,
		logger:                log,
		stats:                 stats,
		payloadsMetadataStore: payloadsMetadataStore,
	}, nil
}

func (s *payloadStoreBlob) Persist(ctx context.Context, workflowBuildID int64, eventPayload []byte, _ types.GlobalID) (int64, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	accountID, accountName := s.sharder.GetRandomAccount()

	s.stats.Counter(ctx, "payloads.account_usage", statter.Tags{"account_id": fmt.Sprintf("%d", accountID), "account_name": accountName}, 1)

	path := payloadPath(workflowBuildID)

	if err := s.blobClient.WriteObject(ctx, accountName, s.container, path, eventPayload); err != nil {
		return 0, tracing.RecordError(span, err)
	}

	// Persist metadata to the database for later retrieval
	if err := s.payloadsMetadataStore.Persist(ctx, workflowBuildID, accountID, version); err != nil {
		return 0, tracing.RecordError(span, err)
	}

	s.stats.Counter(ctx, "payloads.blob.persist", statter.Tags{"account_id": fmt.Sprintf("%d", accountID), "account_name": accountName}, 1)

	return int64(accountID), nil
}

func (s *payloadStoreBlob) Get(ctx context.Context, workflowBuildID int64, _ types.GlobalID) ([]byte, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	metadata, exists, err := s.payloadsMetadataStore.Get(ctx, workflowBuildID)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	if !exists {
		s.stats.Counter(ctx, "payloads.blob.metadata_not_found", statter.Tags{}, 1)
		return nil, tracing.RecordError(span, ErrPayloadMetadataNotFound)
	}

	if metadata == nil {
		return nil, tracing.RecordError(span, errors.New("payload metadata was nil"))
	}

	// GET Account name from accountID metadata
	accountName := s.sharder.GetAccountName(int(metadata.StorageAccountID))

	object, err := s.blobClient.GetObject(ctx, accountName, s.container, payloadPath(workflowBuildID))
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	s.stats.Counter(ctx, "payloads.blob.get", statter.Tags{"account_id": fmt.Sprintf("%d", metadata.StorageAccountID), "account_name": accountName}, 1)

	return object.Content, nil
}

func payloadPath(workflowBuildID int64) string {
	// get the byte representation of the workflowBuildID
	b := make([]byte, 8)
	binary.LittleEndian.PutUint64(b, uint64(workflowBuildID))

	// hash the workflow build database ID
	hashValue := sha256.Sum256(b)

	// Convert hash to a hexadecimal string and truncate to the first 3 characters
	truncatedHash := fmt.Sprintf("%.3x", hashValue)

	// Format the payload path using the truncated hash and the workflowBuildID
	payloadPath := fmt.Sprintf("%s-%d.json", truncatedHash, workflowBuildID)
	return payloadPath
}

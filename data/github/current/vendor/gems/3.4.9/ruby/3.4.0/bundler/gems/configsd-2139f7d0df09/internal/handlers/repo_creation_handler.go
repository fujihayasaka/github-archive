// Package handlers contains message handlers for handling different types of Hydro events.
package handlers

import (
	"context"
	"errors"
	"fmt"

	repositoriesv1 "github.com/github/configsd/internal/hydro/schemas/github/repositories/v1"
	"github.com/github/configsd/internal/model"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-server/runtime/features"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"google.golang.org/protobuf/proto"
)

// RepoCreationHandlerTopic is the Hydro topic for GitHub repository creation events.
const RepoCreationHandlerTopic = "github.repositories.v1.Created"

// NewRepoCreationHandler returns a hydro.MessageHandler that processes GitHub repository
// creation events (repositoriesv1.Created) and updates a Configsd-backed store with the
// repository owner mapping.
//
// Parameters:
//   - configStore: a model.Store used to persist repository owner mappings.
//   - logger: a github.com/github/github-telemetry-go/log.Logger used to emit structured logs.
//   - cancelFunc: a context.CancelFunc that will be called to stop the consuming pipeline for
//     irrecoverable errors (e.g., deserialization or datastore failures).
//
// Notes and guarantees:
//   - Unprocessible messages cause the pipeline to be cancelled
//   - The data store failing to persist data causes the pipeline to be cancelled
//   - The function is safe regarding integer conversions: it validates that the incoming
//     int64/Int32 values are non-negative before converting to uint64.
func NewRepoCreationHandler(configStore model.Store, logger log.Logger, flagger features.Flagger, cancelFunc context.CancelFunc) hydro.MessageHandler {
	logBadMessage := func(hm hydro.Message, level log.Level, err error) {
		logger.Log(level, err.Error(),
			kvp.String("topic", hm.Topic),
			kvp.Int32("partition", hm.Partition),
			kvp.Int64("offset", hm.Offset),
		)
	}

	return func(ctx context.Context, hm hydro.Message) error {
		repoID, ownerID, err := extractIDs(&hm)
		if err != nil {
			if errors.Is(err, ErrUnmarshalFailed) {
				logBadMessage(hm, log.ErrorLevel, err)
				cancelFunc()
				return err
			}
			if errors.Is(err, ErrNullOwnerID) {
				logBadMessage(hm, log.ErrorLevel, err)
				// We don't cancel the context here because this is not an irrecoverable error.
				// The message is malformed, but we can continue processing other messages (hopefully).
				return nil
			}
			if errors.Is(err, ErrNegativeID) {
				// Negative IDs are invalid but not irrecoverable. We log a warning and skip the message.
				logBadMessage(hm, log.WarnLevel, err)
				return nil
			}
			logBadMessage(hm, log.ErrorLevel, err)
			return nil
		}

		if flagger.IsEnabledWithDefaultValue(ctx, "configsd_persist_repo_owners", false) {
			if err := configStore.SetRepositoryOwner(ctx, repoID, ownerID); err != nil {
				msg := "Failed to set repository owner in db"
				logger.Error(msg, kvp.String("error", err.Error()))
				cancelFunc()
				return fmt.Errorf("%s: %w", msg, err)
			}
		}

		logger.Debug("Message processed.", kvp.String("topic", hm.Topic), kvp.Int32("partition", hm.Partition), kvp.Int64("offset", hm.Offset))
		return nil
	}
}

var (
	// ErrUnmarshalFailed indicates that protobuf message unmarshaling failed
	ErrUnmarshalFailed = errors.New("failed to unmarshal message")
	// ErrNullOwnerID indicates that the owner ID field is nil
	ErrNullOwnerID = errors.New("owner ID is nil")
	// ErrNegativeID indicates that an ID field contains a negative value
	ErrNegativeID = errors.New("ID is negative")
)

func extractIDs(hm *hydro.Message) (repoID, ownerID uint64, err error) {
	var event repositoriesv1.Created

	// If we are unable to unmarshal the message, we don't want to continue trying to process it and we also
	// don't want to just skip over it either. Let's log the error, cancel the context to stop further processing,
	// and return the error to ensure the message is not marked as processed.
	if err := proto.Unmarshal(hm.Value, &event); err != nil {
		return 0, 0, ErrUnmarshalFailed
	}

	// This is absurd and should never happen. Let's log it loudly and skip the message.
	if event.Repository.OwnerId == nil {
		return 0, 0, ErrNullOwnerID
	}

	// Safely convert int64 and int32 to uint64
	signedRepoID := event.RepositoryId
	ownerIDValue := event.Repository.OwnerId.GetValue()

	if signedRepoID < 0 || ownerIDValue < 0 {
		return 0, 0, ErrNegativeID
	}

	repoID = uint64(signedRepoID)
	ownerID = uint64(ownerIDValue)

	return repoID, ownerID, nil
}

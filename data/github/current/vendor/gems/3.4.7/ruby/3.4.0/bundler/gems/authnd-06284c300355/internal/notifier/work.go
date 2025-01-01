package notifier

import (
	"context"
	"strconv"
	"strings"
	"time"

	"github.com/pkg/errors"

	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/publisher"
	schema "github.com/github/authnd/internal/common/publisher/hydro/schemas/authnd/v0"
	"github.com/github/authnd/internal/common/store"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-ctxutil"
	"github.com/github/go-stats"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// at most 20 tokens in each processing batch
const defaultBatchSize = 20

// the default timeout for each work item
var defaultWorkTimeout = 5 * time.Minute

// the default timeout for each batch of tokens. this needs to be less than the kubelet shutdown grace
// period, 30s by default, to avoid getting a hard interrupt (SIGKILL).
// https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/#hook-handler-execution
var defaultBatchTimeout = 10 * time.Second

func newWork(
	lookupTokens func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error),
	eventType schema.ProgrammaticAccessEventEventType,
	eventReason string,
	eventer publisher.PratEventPublisher,
	store store.ProgrammaticAccessTokensStore,
	isProxima bool,
) *work {
	return &work{
		lookupTokens:       lookupTokens,
		eventType:          eventType,
		eventReason:        eventReason,
		eventer:            eventer,
		markTokenEvents:    store.MarkEventForProgrammaticAccessTokens,
		businessIdForToken: store.BusinessIdForProgrammaticAccessToken,
		timeout:            defaultWorkTimeout,
		batchTimeout:       defaultBatchTimeout,
		batchSize:          defaultBatchSize,
		isProxima:          isProxima,
	}
}

type work struct {
	lookupTokens       func(ctx context.Context, lastID uint64, batchSize int64) ([]*models.ProgrammaticAccessToken, error)
	eventType          schema.ProgrammaticAccessEventEventType
	eventReason        string
	eventer            publisher.PratEventPublisher
	markTokenEvents    func(context.Context, []uint64) error
	businessIdForToken func(context.Context, uint64) (uint64, error)
	timeout            time.Duration
	batchTimeout       time.Duration
	batchSize          int64
	isProxima          bool
}

// Process work for the configured class of tokens (in batches):
// 1. Lookup tokens
// 2. Emit events to hydro, one token at a time
// 3. Update `last_event_at_utc` for all tokens with emitted events (one txn)
func (w *work) Do(ctx context.Context) error {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	start := time.Now()
	var success bool
	var totalProcessed int
	defer func() {
		tags := stats.Tags{"success": strconv.FormatBool(success)}
		statter.Distribution("job.work.processed", tags, float64(totalProcessed))
		statter.DistributionMs("job.work.duration", tags, time.Since(start))
	}()
	logger.Info("starting work")

	ctx, cancel := context.WithTimeout(ctx, w.timeout)
	defer cancel()

	var lastID uint64
	for {
		// 1. Lookup tokens
		tokens, err := w.lookupTokens(ctx, lastID, w.batchSize)
		if err != nil {
			// we can't proceed beyond this point without potentially missing some notifications
			logger.WithError(err).Error("Unable to lookup tokens for notification")
			return err
		}

		if len(tokens) == 0 {
			// no more tokens to process for this event type
			break
		}
		statter.Distribution("job.work.batch.size", nil, float64(len(tokens)))

		err = w.doBatch(ctx, tokens)
		if err != nil {
			logger.WithError(err).Error("Failure processing batch")
			return err
		}

		if len(tokens) < int(w.batchSize) {
			// no more tokens to process this time around (i.e. we're at the 'bottom of the barrel')
			break
		}

		if err := ctx.Err(); err != nil {
			logger.WithError(err).Error("Context is done, exiting early")
			return err
		}

		// update the ID for the last observed token, this is required for record pagination
		lastID = tokens[len(tokens)-1].ID
	}
	logger.Info("finished processing tokens", kvp.Int("gh.authnd.notifier.processed", totalProcessed), kvp.Duration("gh.authnd.notifier.duration", time.Since(start)))
	success = true

	return nil
}

// Execute the work needed for a batch.  each batch gets its own context which has a timeout and
// is detached from the parent to avoid messy context cancellation handling.  To ensure graceful
// shutdowns, the batch timeout MUST be less than the pod termination grace period (see
// 'defaultBatchTimeout' above).
func (w *work) doBatch(ctx context.Context, tokens []*models.ProgrammaticAccessToken) error {
	logger := diagnostics.Logger(ctx)
	statter := diagnostics.Statter(ctx)

	var cancel context.CancelFunc
	batchCtx := ctxutil.DetachedCancel(ctx)
	batchCtx, cancel = context.WithTimeout(batchCtx, w.batchTimeout)
	defer cancel()

	batchStart := time.Now()

	// 2. Emit events to hydro, one token at a time
	processedTokens := make([]uint64, 0, w.batchSize)
	for _, token := range tokens {
		message := schema.ProgrammaticAccessEvent{
			ActorId:                int64(token.MintTokenCommon.ActorID),
			CredentialId:           int64(token.ID),
			AccessId:               int64(token.AccessID),
			CredentialSuffix:       string(token.TokenSuffix),
			CredentialIssuedAtUtc:  timestamppb.New(token.MintTokenCommon.IssuedAt),
			CredentialExpiresAtUtc: token.ExpiresAt.ToProto(),
			EventType:              w.eventType,
			EventReason:            w.eventReason,
			SendNotification:       true,
			CatalogService:         serviceName,
			RequestId:              JobID,
		}

		if w.isProxima {
			tenantId, err := w.businessIdForToken(ctx, token.ID)
			if err != nil {
				logger.WithError(err).Error("Failed to lookup tenant ID for token")
			}
			message.TenantId = int64(tenantId)
		}
		if w.eventType == schema.ProgrammaticAccessEvent_REVOKED {
			// Don't trigger notifications for revoke requests that we've caught here.  They may have been initiated by
			// secret scanning, in which case we don't want to notify the user directly.
			message.SendNotification = false
		}

		err := w.eventer.PublishEvent(ctx, message)
		if err != nil {
			logger.WithError(err).Info("Failed to emit hydro message for token", kvp.Uint64("gh.authnd.notifier.token.id", token.ID))
			statter.Counter("job.work.publish_failure.count", nil, 1)
			continue
		}
		logger.Debug("Emitted hydro message for token", kvp.Uint64("id", token.ID))
		processedTokens = append(processedTokens, token.ID)
	}

	numProcessedTokens := len(processedTokens)
	if numProcessedTokens == 0 {
		logger.Error("Failed to emit hydro messages for any of the provided tokens", kvp.String("gh.authnd.notifier.token.ids", joinIDs(idList(tokens))))
		return errors.New("failed to process any tokens in batch")
	}

	err := common.WithRetries(batchCtx, "notifier_mark_tokens",
		func(ctx context.Context) error {
			return w.markTokenEvents(ctx, processedTokens)
		}, 3)
	if err != nil {
		logger.WithError(err).Error("Unable to mark tokens as notified", kvp.String("gh.authnd.notifier.processed.ids", joinIDs(processedTokens)))
		statter.Counter("job.work.mark_tokens_failure.count", nil, 1)
		return err
	}

	logger.Info("successfully processed batch of tokens",
		kvp.Int("gh.authnd.notifier.processed", numProcessedTokens),
		kvp.Int("gh.authnd.notifier.batch.size", len(tokens)),
		kvp.Int("gh.authnd.notifier.max.batch.size", int(w.batchSize)),
		kvp.Duration("gh.authnd.notifier.batch.duration", time.Since(batchStart)),
	)
	statter.DistributionMs("job.work.batch.duration", nil, time.Since(batchStart))
	return nil
}

func joinIDs(ids []uint64) string {
	if len(ids) == 0 {
		return ""
	}
	var builder strings.Builder

	first, ids := ids[0], ids[1:]
	builder.WriteString(strconv.Itoa(int(first)))
	for _, id := range ids {
		builder.WriteString(",")
		builder.WriteString(strconv.Itoa(int(id)))
	}
	return builder.String()
}

func idList(tokens []*models.ProgrammaticAccessToken) []uint64 {
	ids := make([]uint64, 0, len(tokens))
	for _, token := range tokens {
		ids = append(ids, token.ID)
	}
	return ids
}

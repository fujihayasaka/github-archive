package deltaingest

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/blackbird/crates/client/pkg/blackbird"
	indexpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/index/v1"
	"github.com/github/blackbird/crates/core/pkg/geometricfilter"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/crawl"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
	"github.com/github/blackbird-mw/internal/document"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/spokesd"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

// NOTE: We add 10 minutes to the process's current time to set the initial
// expires at time. We assume clocks will not be skewed by enough for this to
// matter.
//
// If we need a central time source, we can use MySQL when generating the
// sequence number.
const initialLeaseDuration = 10 * time.Minute

// Sentinel error returned when a crawl is complete, but the repo/sequence
// number doesn't match. This means there's more to crawl.
var errMoreToIngest = errors.New("ingest sucessful, but still more to do")

// Sentinel error returned when we should restart the ingest without deducting a retry.
var errRetryIngest = errors.New("retry ingest")

// An operation that ingests a repository using the new IndexQueryAPI.
type IndexAPIIngestOp struct {
	offsetTracker  *kafka.OffsetTracker
	crawlPool      *crawl.WorkPool
	githubClient   github.InternalAPIClient
	gitClient      gitaccess.Client
	store          db.Store
	indexerCluster *routing.IndexerCluster
	topicConfig    routing.TopicConfig
	retries        int
}

func NewIndexAPIIngestOp(
	offsetTracker *kafka.OffsetTracker,
	crawlPool *crawl.WorkPool,
	githubClient github.InternalAPIClient,
	gitClient gitaccess.Client,
	store db.Store,
	indexerCluster *routing.IndexerCluster,
	topicConfig routing.TopicConfig,
	retries int,
) *IndexAPIIngestOp {
	return &IndexAPIIngestOp{
		offsetTracker,
		crawlPool,
		githubClient,
		gitClient,
		store,
		indexerCluster,
		topicConfig,
		retries,
	}
}

func (o *IndexAPIIngestOp) Run(task *Task) {
	task.Begin(o)

	start := time.Now()
	ctx := task.ctx
	statting.DistributionMs(ctx, "ingest.consumer.task.queued_ms", time.Since(task.receivedAt))

	// Allow any part of the ingest process to perform conditional work based on
	// the cluster environment.
	ctx = experiments.WithCluster(ctx,
		&experiments.ClusterEnv{
			EpochID:     task.corpus.EpochID,
			ClusterName: task.corpus.Corpus.ClusterName(),
			CorpusName:  task.corpus.Corpus.String(),
		})

	skip, err := o.ingestWithRetry(ctx, task)
	if err != nil {
		statting.DistributionMs(ctx, "ingest.consumer.task.process.duration", time.Since(start), stats.Tags{"status": status(skip, err)})

		if errors.Is(err, context.Canceled) {
			logging.Error(ctx, "ingest task interrupted due to context cancellation", kvp.Err(err))
			task.Done(err) // we are shutting down. report the error so the offsets can't be marked.
		} else if errors.Is(err, ErrEpochChanged) {
			// Special case: this isn't the repo's fault, so don't mark it as permanently failed.
			logging.Error(ctx, "detected epoch mismatch", kvp.Err(err))
			task.Done(err) // restart the process
		} else {
			logging.Error(ctx, "marking retries exhausted due to error", kvp.Err(err))
			if err := o.markRetriesExhausted(ctx, task, err); err != nil {
				logging.Error(ctx, "failed to mark retries exhausted for repo", kvp.Err(err))
			}
			task.Done(nil) // supress the error so the process doesn't restart. Offsets will be marked which is desired because we are skipping this repo.
		}

		return
	}

	if skip != nil {
		logging.Info(ctx, "skipping repository ingest", kvp.String("reason", skip.String()))
	}

	statting.DistributionMs(ctx, "ingest.consumer.task.process.duration", time.Since(start), stats.Tags{"status": status(skip, nil)})
	task.Done(nil)
}

func (o *IndexAPIIngestOp) OnDone(task *Task, err error) {
	panic("OnDone called in IndexAPIIngestOp which is a sink operation")
}

// Any error out of this means retries are exhausted (or given up) and we should
// mark this task's repo as premanently failed.
func (o *IndexAPIIngestOp) ingestWithRetry(ctx context.Context, task *Task) (*db.SkipReason, error) {
	var skip *db.SkipReason
	attempt := 0
	operation := func() error {
		attempt++

		ctx := logging.With(ctx, kvp.Int("index_api_ingest_attempt", attempt))

		var err error
		skip, err = o.ingestInner(ctx, task)
		if err != nil {
			var permErr *permanentError
			if errors.As(err, &permErr) {
				logging.Error(ctx, "ingest operation failed (permanent)", kvp.String("category", permErr.legacyReason()), kvp.Int("repo_id", int(permErr.repoID)), kvp.Err(err))
				o.markPermanentError(ctx, task.corpus.EpochID, permErr, task.messageID())
				return nil
			}

			logging.Error(ctx, "ingest attempt failed", kvp.Err(err))
		}
		return err
	}

	// Any of these errors should be retried without deducting an attempt.
	errsToAlwaysRetry := []error{
		errRetryIngest, mysqlerrors.DeadlockError(), mysqlerrors.NoWaitLockError(), mysqlerrors.QueryInterruptedError(),
		mysqlerrors.ServerShutdownError(), mysqlerrors.GoneAwayError(), mysqlerrors.LostConnectionError(),
	}

	err := retry.WithExceptions(ctx, operation, uint64(o.retries), errsToAlwaysRetry...)
	if err != nil {
		logging.Error(ctx, "ingest operation failed after retries", kvp.Int("index_api_ingest_attempt", attempt), kvp.Err(err))
	}
	return skip, err
}

func (o *IndexAPIIngestOp) ingestInner(ctx context.Context, task *Task) (*db.SkipReason, error) {
	start := time.Now()
	defer func() { statting.DistributionMs(ctx, "worker.ingest.delta_ingest.phase4", time.Since(start)) }()

	// NOTE: This is not a great metric name, but it's defined by IndexOp and
	// used in a dashboard, so I'm keeping it as-is in an equivalent place for
	// IndexAPIIngestOp.
	statting.Counter(ctx, "worker.messages", 1)
	logging.Info(ctx, "attempting to ingest repository with IndexQueryAPI")

	if skip := shouldSkipTask(task); skip != nil {
		return skip, nil
	}

	skip, err := o.shouldSkipPermanentError(ctx, task)
	if err != nil {
		return nil, err
	}

	if skip != nil {
		return skip, nil
	}

	statting.DistributionMs(ctx, "worker.ingest.delta_ingest.phase0", time.Since(start))
	result, err := o.store.RepositorySequence(ctx, task.repoID(), func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		logging.Info(ctx, "running callback to get repository info")
		info, err := o.githubClient.GetRepository(ctx, task.repoID())
		if err != nil {
			return nil, nil, nil, err
		}

		if reason := shouldSkipRepository(info, state, task.msg.Topic, task.stamp, o.indexerCluster.EpochMode()); reason != nil {
			return reason, nil, nil, nil
		}

		head, err := o.gitClient.GetDefaultRef(ctx, task.repoID())
		if err != nil {
			return nil, nil, nil, newTransientError(err, info.NWO())
		}

		// The head of the default ref can't be found: crawling will fail. It
		// might succeed in the future if the repo changes (e.g., gets its first
		// push). Skip it for now, but don't ban the repo.
		if head == nil {
			return &db.SkipDefaultRefOIDNotFound, nil, nil, nil
		}

		return nil, info, head, nil
	})

	statting.DistributionMs(ctx, "worker.ingest.delta_ingest.phase1", time.Since(start))

	if err != nil {
		switch {
		case errors.Is(err, context.DeadlineExceeded):
			// Check this first, because the deadline can trip anywhere.
			// See https://github.com/github/blackbird/issues/7044
			logging.Error(ctx, "repository sequence callback timed out", kvp.Err(err))
			return nil, err
		case errors.Is(err, github.ErrRepoNotFound), errors.Is(err, github.ErrRepoDisabled), errors.Is(err, github.ErrRepoBlocked):
			logging.Info(ctx, "repository not found, disabled, or blocked; marking as deleted", kvp.Err(err))
			sourceKafkaOffsets := getSourceOffsets(o.offsetTracker, task.messageID().Topic, task.messageID().Partition)
			return nil, o.markDeleted(ctx, task.corpus.EpochID, task.repoID(), sourceKafkaOffsets)
		case spokesd.IsGitmonTooManyProcessesError(err):
			// A git RPC failed fast due to the too-many-processes error. We should retry later.
			logging.Info(ctx, "git RPC failed by gitmon, will retry", kvp.Err(err))
			return nil, errRetryIngest
		case spokesd.IsInvalidRefError(err):
			// An invalid ref is a serious problem: the OID is invalid or the
			// branch name can't be indexed (e.g., non-UTF-8). Ban this repo so
			// we have a way to tell the user their repo needs to be changed.
			return nil, o.markInvalidDefaultRef(ctx, task, err)
		default:
			logging.Error(ctx, "failed to sequence repository", kvp.Err(err))
			return nil, err
		}
	}

	if result.IsSkip() {
		logging.Info(ctx, "skipping repository ingest after fetching details", kvp.String("reason", result.SkipReason.String()))
		return result.SkipReason, nil
	}

	ctx = logging.With(
		ctx,
		kvp.Bool("is_public", result.Repository.IsPublic),
		kvp.Int("num_stars", int(result.Repository.NumStars.Int32)),
		kvp.Int("owner_id", int(result.Repository.OwnerID)),
		kvp.String("nwo", result.Repository.NWO()),
		kvp.Int("network_id", int(result.Repository.NetworkID.Int32)),
		kvp.String("head_oid", result.RefTip.CommitOID.String()),
		kvp.String("ref_name", result.RefTip.RefName),
		kvp.Any("experiments", result.Repository.Experiments),
		kvp.Int64("commit_seq_no", result.Repository.CommitSeqNo.Int64),
		kvp.Int64("repo_seq_no", result.Repository.RepoSeqNo.Int64),
		// TODO: Do we want to store paying_customer?
		kvp.Bool("paying_customer", result.GitHubRepository.PayingCustomer),
	)

	// Set initialCommitSeqNo to the first successful commit sequence number
	if task.initialCommitSeqNo > uint64(result.Repository.CommitSeqNo.Int64) {
		task.initialCommitSeqNo = uint64(result.Repository.CommitSeqNo.Int64)
	}

	msg := o.newIngestMsg(task, result)
	res, err := o.startIngest(ctx, msg)
	if err != nil {
		return nil, err
	}
	statting.DistributionMs(ctx, "worker.ingest.delta_ingest.phase2", time.Since(start))

	switch res.IngestStatus {
	case indexpb.IngestStatus_INGEST_STATUS_SUCCESS:
		logging.Info(ctx, "ingest status success, done")
		return nil, nil
	case indexpb.IngestStatus_INGEST_STATUS_PERMANENT_FAILURE:
		logging.Info(ctx, "ingest status permanent failure, aborting")
		return nil, nil
	case indexpb.IngestStatus_INGEST_STATUS_COMMIT_NOT_FOUND:
		logging.Info(ctx, "ingest status commit not found, aborting")
		return nil, nil
	case indexpb.IngestStatus_INGEST_STATUS_IN_PROGRESS:
		// Re-create the message based on what the indexer told us to crawl
		msg = o.newIngestMsgFromResponse(task, res)

		var locationLimit int
		if task.repoID() == msg.RepoID {
			locationLimit = maxBlobLocations(msg.RepoID, result.Repository.NumStars.Int32, result.GitHubRepository.PayingCustomer)
		} else {
			// If the indexer told us to crawl a different repository than the one we
			// requested an index for, we need to look up the new repo's metadata to
			// determine its location limit.
			repo, err := o.githubClient.GetRepository(ctx, msg.RepoID)
			if err != nil {
				switch {
				case errors.Is(err, github.ErrRepoNotFound), errors.Is(err, github.ErrRepoDisabled), errors.Is(err, github.ErrRepoBlocked):
					logging.Info(ctx, "repository not found, disabled, or blocked; marking as deleted", kvp.Err(err))
					sourceKafkaOffsets := getSourceOffsets(o.offsetTracker, task.messageID().Topic, task.messageID().Partition)
					return nil, o.markDeleted(ctx, msg.EpochID, msg.RepoID, sourceKafkaOffsets)
				default:
					logging.Error(ctx, "error re-fetching repository to check max locations", kvp.Err(err))
					return nil, err
				}
			}
			locationLimit = maxBlobLocations(msg.RepoID, repo.NumStars, repo.PayingCustomer)
		}

		parentCommitOID := gitaccess.NullObjectID
		if len(msg.ParentCommitSHA) > 0 {
			parentCommitOID = gitaccess.NewObjectIDFromBytes(msg.ParentCommitSHA)
		}

		ctx = logging.With(
			ctx,
			kvp.Uint64("entry_id", msg.EntryID),
			kvp.Uint64("parent_entry_id", msg.ParentEntryID),
			kvp.String("indexer_commit_oid", msg.Head.CommitOID.String()),
			kvp.String("indexer_parent_commit_oid", parentCommitOID.String()),
			kvp.Uint64("indexer_commit_seq_no", msg.CommitSeqNo),
			kvp.Uint64("indexer_repo_seq_no", uint64(msg.RepoSeqNo)),
			kvp.Uint64("indexer_repo_id", uint64(msg.RepoID)),
			kvp.Uint("indexer_parent_repo_id", uint(msg.ParentRepoID)),
			kvp.Int64("index_response_serving_offset", msg.ServingOffset),
			kvp.Int("location_limit", locationLimit),
		)

		// The indexer somehow returned an older repo seq no than the one sent
		// in the index request. There is something wrong in the indexer, abort.
		if types.RepoID(res.RepoId) == msg.RepoID && types.RepoSeqNo(res.RepoSeqNo) < msg.RepoSeqNo {
			panic("indexer repo_seq_no is behind")
		}

		filter, topicBarrier, err := o.crawl(ctx, msg, locationLimit)
		statting.DistributionMs(ctx, "worker.ingest.delta_ingest.phase3", time.Since(start))

		if err != nil {
			switch {
			case errors.Is(err, crawl.ErrMessageSizeTooLarge):
				// A document in this repo has so many locations that it exceeds the
				// Kafka broker's 5MB max message size. This is considered fatal
				// (retrying will not change anything) and the repo is permanently
				// marked as non-crawlable.
				return nil, newPermanentError(err, blackbird_entities.PermanentErrorType_SYSTEM_LIMIT, msg.RepoID, msg.CommitSeqNo, msg.RepoSeqNo)
			case spokesd.IsInvalidDiffBaseError(err):
				// NOTE: When the base is invalid, the indexer must mark the
				// parent entry as purged. It should NOT be possible to have an
				// invalid base without a parent, so we panic.
				//
				// TODO: IsInvalidDiffBaseError also covers the base repo being
				// deleted (as reported by spokesd). It might be nice to be able
				// to distinguish that, so it can be marked deleted in the
				// index?
				if msg.ParentEntryID == 0 || msg.ParentRepoID == 0 {
					panic(fmt.Sprintf("invariant violated: invalid diff base error without parent entry and repo: %+v", err))
				}

				if err := o.finalize(
					ctx,
					msg.EpochID,
					msg.RepoID,
					msg.EntryID,
					indexpb.IngestStatus_INGEST_STATUS_COMMIT_NOT_FOUND,
					err.Error(),
					nil, // filter
					nil, // barrier
					task.messageID(),
				); err != nil {
					return nil, err
				}

				// return the crawl error so we can retry with a (hopefully) new base from the indexer.
				//
				// Since the issue was with the parent commit (which was
				// previously indexed), this problem shouldn't count against a
				// repo's attempts so we return errRetryIngest.
				return nil, errors.Join(errRetryIngest, err)
			case spokesd.IsInvalidCommitError(err):
				// The HEAD commit is invalid.
				//
				// TODO: Retrying on a subsequent push *might* work in some cases, but
				// this specific commit will never successfully ingest. For now we
				// require human intervention to fix.
				return nil, newPermanentError(err, blackbird_entities.PermanentErrorType_BAD_COMMIT, msg.RepoID, msg.CommitSeqNo, msg.RepoSeqNo)
			case errors.Is(err, document.ErrAbusiveRepoContent) || spokesd.IsGitSystemError(err) || spokesd.IsLocationLimitExceededError(err) || errors.Is(err, errTooManyBlobLocations):
				// FIXME: ErrAbusiveRepoContent is apparently never used -- remove?
				//
				// We do not want to index any repo that has abusive content e.g. a repo containing
				// documents with too many locations pointing to the same blob are considered abusive.
				// gitbombs fall into this category.
				return nil, newPermanentError(err, blackbird_entities.PermanentErrorType_SYSTEM_LIMIT, msg.RepoID, msg.CommitSeqNo, msg.RepoSeqNo)
			case document.IsInvalidDocument(err):
				// There was an error converting this repository's content to GitDocuments. Retrying will not help.
				//
				// TODO: This represents an invariant that was violated. Should this shut down the process instead?
				return nil, newPermanentError(err, blackbird_entities.PermanentErrorType_RETRIES_EXHAUSTED, msg.RepoID, msg.CommitSeqNo, msg.RepoSeqNo)
			default:
				logging.Error(
					ctx,
					"failed to ingest repo",
					kvp.Any("duration", time.Since(start)),
					kvp.Duration("duration_ms", time.Since(start)),
					kvp.Err(err),
				)

				return nil, newTransientError(err, msg.NWO())
			}
		}

		err = o.finalize(ctx, msg.EpochID, msg.RepoID, msg.EntryID, indexpb.IngestStatus_INGEST_STATUS_SUCCESS, "", filter, topicBarrier, task.messageID())
		if err != nil {
			return nil, newTransientError(err, msg.NWO())
		}

		// If the repo ID matches and the indexer's commit sequence number is
		// greater than or equal to the _initial_ sequence number, we're done.
		//
		// Originally, this required the indexer's commit sequence number to
		// equal the CURRENT sequence number, but for frequently pushed
		// repositories, we would run out of retries.
		//
		// TODO(rewinfrey): Update to also verify the repo sequence number after backfilling all corpora.
		if msg.RepoID == task.repoID() && res.CommitSeqNo >= task.initialCommitSeqNo {
			logging.Info(ctx, "ingest successful with same repo ID and equal or greater sequence number")
			return nil, nil
		}

		// NOTE: If the repo is never up-to-date with the sequence number, this
		// will eventually run out of retries and mark the repo as permanently
		// failed. However, we expect this not to happen, because there will
		// typically only be a single additional crawl to finish (the prior
		// commit).
		logging.Info(
			ctx,
			"ingest sucessful with sequence number or repo ID mismatch, retrying",
			kvp.Int64("commit_seq_no", result.Repository.CommitSeqNo.Int64),
			kvp.Uint64("res_commit_seq_no", res.CommitSeqNo),
			kvp.Int64("repo_seq_no", result.Repository.RepoSeqNo.Int64),
			kvp.Uint64("res_repo_seq_no", res.RepoSeqNo),
		)
		return nil, newTransientError(errMoreToIngest, msg.NWO())
	default:
		panic(fmt.Sprintf("unexpected IngestStatus: %s", res.IngestStatus.String()))
	}
}

// getNewEpochError attempts to retrieve the serving status from an
// error and checks if the serving status indicates a new epoch, and returns an
// error if so, allowing the caller to determine if the error should be retried.
func getNewEpochError(ctx context.Context, taskEpochID types.EpochID, err error) error {
	status, statusErr := blackbird.ServingStatus(err)
	if statusErr != nil {
		logging.Error(ctx, "failed to get serving status from err", kvp.Err(statusErr))
		return nil
	}

	if status != nil && status.EpochId != uint32(taskEpochID) {
		return fmt.Errorf("%w: processing epoch %d, indexer is on epoch %d", ErrEpochChanged, uint32(taskEpochID), status.EpochId)
	}

	return nil
}

// Send an RPC to create an entry and return the response. Retries forever until
// successful AND the response is doesn't have state
// IngestStatus_INGEST_STATUS_INVALID.
func (o *IndexAPIIngestOp) startIngest(ctx context.Context, msg *messages.Ingest) (*indexpb.IndexResponse, error) {
	attempt := 0
	var res *indexpb.IndexResponse
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Err(err))
			return err
		}

		var suggestedChildID *wrapperspb.UInt32Value
		if msg.RepoNode().PreallocatedChildID != 0 {
			suggestedChildID = wrapperspb.UInt32(msg.RepoNode().PreallocatedChildID)
		}

		req := &indexpb.IndexRequest{
			ShardId:     host.ShardID,
			EpochId:     uint32(msg.EpochID),
			CommitSeqNo: msg.CommitSeqNo,
			Repo: &indexpb.Repository{
				RepoId:          uint32(msg.RepoID),
				OwnerId:         msg.OwnerID,
				NetworkId:       uint32(msg.NetworkID),
				Nwo:             msg.NWO(),
				IsPublic:        msg.IsPublic,
				IsArchived:      msg.IsArchived,
				IsFork:          msg.IsFork,
				RepoScore:       msg.RepoScore,
				LicenceName:     msg.LicenseName.String,
				NumWatchers:     uint32(msg.NumWatchers),
				NumStars:        uint32(msg.NumStars),
				HasReadMe:       msg.HasReadme,
				PublicForkCount: uint32(msg.PublicForkCount),
				Experiments:     msg.DotcomExperiments,
				RepoSeqNo:       uint64(msg.RepoSeqNo),
			},
			ParentRepoIds:      msg.RepoNode().AncestorsUint32s(),
			SuggestedChildId:   suggestedChildID,
			CommitSha:          msg.Head.CommitOID.Bytes(),
			RefName:            msg.Head.RefName,
			Reindex:            msg.IsReindex(),
			ExpiresAt:          msg.IngestStartedAt.Add(initialLeaseDuration).UnixMilli(),
			SourceKafkaOffsets: getSourceOffsets(o.offsetTracker, msg.Topic, msg.Partition),
		}

		idxRes, err := host.Index(ctx, req)
		if err != nil {
			logging.Error(ctx, "Index RPC failed", kvp.Err(err), kvp.Int("index_rpc_attempt", attempt), kvp.String("index_host", host.Hostname))
			if epochMovedErr := getNewEpochError(ctx, msg.EpochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}

			// NOTE: The IndexQueryAPI returns deadline_exceeded when we've been
			// retrying so long that `ExpiresAt` has passed. Return a Permanent
			// error wrapping errRetryIngest to restart from the top.
			if retry.IsTwirpDeadlineExceeded(err) {
				return backoff.Permanent(fmt.Errorf("%w: %w", errRetryIngest, err))
			}

			return err
		}

		// NOTE: We guarantee this method will not return an invalid ingest
		// status so downstream consumers can rely on that and not have to redo
		// work.
		if idxRes.IngestStatus == indexpb.IngestStatus_INGEST_STATUS_INVALID {
			logging.Error(ctx, "Index RPC returned invalid status, retrying", kvp.Int("index_rpc_attempt", attempt), kvp.String("index_host", host.Hostname))
			return errors.New("invalid ingest state")
		}

		res = idxRes
		return nil
	}

	err := backoff.Retry(op, retry.Forever(ctx))
	if err != nil {
		return nil, err
	}

	return res, nil
}

// Send a PermanentError RPC for a permanentError, using that permanentError's
// repository ID, commit sequence number, and failure classification.
//
// Infailable, because if this fails, we already errored out and we don't want
// to supercede that error. If this fails, a NEW snapshot will remain in the
// index. Upon a subsequent crawl of the repo, it will either be finished
// successfully, or will be marked a permanent error then.
func (o *IndexAPIIngestOp) markPermanentError(ctx context.Context, epochID types.EpochID, permErr *permanentError, messageID kafka.MessageID) {
	err := o.permanentError(ctx, epochID, permErr.repoID, types.NWO{}, permErr.commitSeqNo, permErr.repoSeqNo, permErr.errorType, permErr.Description(), messageID)
	if err != nil {
		logging.Error(ctx, "failed to mark permanent error, ignoring", kvp.Err(err))
	}
}

// Create a sequence number for the repository from the task, then send a
// PermanentError RPC for retries exhausted error.
func (o *IndexAPIIngestOp) markRetriesExhausted(ctx context.Context, task *Task, cause error) error {
	seqNos, err := o.store.ErroredRepositorySequence(ctx, task.repoID(), false)
	if err != nil {
		return err
	}

	reason := fmt.Sprintf("retries exhausted: %v", cause)
	return o.permanentError(ctx, task.corpus.EpochID, task.repoID(), nwoFromErr(cause), seqNos.CommitSeqNo, seqNos.RepoSeqNo, blackbird_entities.PermanentErrorType_RETRIES_EXHAUSTED, reason, task.messageID())
}

// Create a sequence number for the repository from the task, then send a DeleteRepository RPC.
func (o *IndexAPIIngestOp) markDeleted(ctx context.Context, epochID types.EpochID, repoID types.RepoID, sourceKafkaOffsets []*blackbird_entities.SourceKafkaOffsets) error {
	seqNos, err := o.store.ErroredRepositorySequence(ctx, repoID, true)
	if err != nil {
		return err
	}

	return o.deleteRepo(ctx, epochID, repoID, seqNos.CommitSeqNo, seqNos.RepoSeqNo, sourceKafkaOffsets)
}

// Create a sequence number for the repository from the task, then send a PermanentError RPC for a default ref invalid error.
func (o *IndexAPIIngestOp) markInvalidDefaultRef(ctx context.Context, task *Task, cause error) error {
	seqNos, err := o.store.ErroredRepositorySequence(ctx, task.repoID(), false)
	if err != nil {
		return err
	}

	reason := fmt.Sprintf("invalid default ref: %v", cause)
	return o.permanentError(ctx, task.corpus.EpochID, task.repoID(), nwoFromErr(cause), seqNos.CommitSeqNo, seqNos.RepoSeqNo, blackbird_entities.PermanentErrorType_INVALID_DEFAULT_REF, reason, task.messageID())
}

// Finalize an entry.
//
// Retries forever until the Finalize RPC succeeds (the most common reason to
// retry is that the DSA client isn't ready).
func (o *IndexAPIIngestOp) finalize(
	ctx context.Context,
	epochID types.EpochID,
	repoID types.RepoID,
	entryID uint64,
	status indexpb.IngestStatus,
	msg string,
	filter []byte,
	barrier *blackbird_entities.TopicBarrier,
	messageID kafka.MessageID, // the message that triggered this finalize, even if it was for a different repo
) error {
	attempt := 0
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Err(err))
			return err
		}

		req := &indexpb.FinalizeRequest{
			ShardId:            host.ShardID,
			EpochId:            uint32(epochID),
			RepoId:             uint32(repoID),
			EntryId:            entryID,
			GeometricXorFilter: filter,
			PermanentError:     msg,
			IngestStatus:       status,
			Barrier:            barrier,
			SourceKafkaOffsets: getSourceOffsets(o.offsetTracker, messageID.Topic, messageID.Partition),
		}

		_, err = host.Finalize(ctx, req)
		if err != nil {
			logging.Error(ctx, "Finalize RPC failed", kvp.Uint64("entry_id", entryID), kvp.Err(err), kvp.Int("finalize_attempt", attempt), kvp.String("index_host", host.Hostname))
			if epochMovedErr := getNewEpochError(ctx, epochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}
			return err
		}

		return nil
	}

	return backoff.Retry(op, retry.Forever(ctx))
}

func (o *IndexAPIIngestOp) deleteRepo(
	ctx context.Context,
	epochID types.EpochID,
	repoID types.RepoID,
	commitSeqNo uint64,
	repoSeqNo types.RepoSeqNo,
	sourceKafkaOffsets []*blackbird_entities.SourceKafkaOffsets,
) error {
	attempt := 0
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Err(err))
			return err
		}

		req := &indexpb.DeleteRepositoryRequest{
			ShardId:            host.ShardID,
			EpochId:            uint32(epochID),
			RepoId:             uint32(repoID),
			CommitSeqNo:        commitSeqNo,
			RepoSeqNo:          uint64(repoSeqNo),
			SourceKafkaOffsets: sourceKafkaOffsets,
		}

		_, err = host.DeleteRepository(ctx, req)
		if err != nil {
			logging.Error(ctx, "DeleteRepository RPC failed", kvp.Int("repo_id", int(repoID)), kvp.Err(err), kvp.Int("delete_repository_attempt", attempt), kvp.String("index_host", host.Hostname))
			if epochMovedErr := getNewEpochError(ctx, epochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}
			return err
		}

		return nil
	}

	return backoff.Retry(op, retry.Forever(ctx))
}

func (o *IndexAPIIngestOp) permanentError(
	ctx context.Context,
	epochID types.EpochID,
	repoID types.RepoID,
	nwo types.NWO,
	commitSeqNo uint64,
	repoSeqNo types.RepoSeqNo,
	errorType blackbird_entities.PermanentErrorType,
	msg string,
	messageID kafka.MessageID,
) error {
	attempt := 0
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Err(err))
			return err
		}

		req := &indexpb.PermanentErrorRequest{
			ShardId:            host.ShardID,
			EpochId:            uint32(epochID),
			RepoId:             uint32(repoID),
			CommitSeqNo:        commitSeqNo,
			RepoSeqNo:          uint64(repoSeqNo),
			PermanentError:     msg,
			SourceKafkaOffsets: getSourceOffsets(o.offsetTracker, messageID.Topic, messageID.Partition),
			Nwo:                nwo.String(),
			PermanentErrorType: errorType,
		}

		_, err = host.PermanentError(ctx, req)
		if err != nil {
			logging.Error(ctx, "PermanentError RPC failed", kvp.Int("repo_id", int(repoID)), kvp.Err(err), kvp.Int("permanent_error_attempt", attempt), kvp.String("index_host", host.Hostname))
			if epochMovedErr := getNewEpochError(ctx, epochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}
			return err
		}

		return nil
	}

	return backoff.Retry(op, retry.Forever(ctx))
}

func (o *IndexAPIIngestOp) crawl(
	ctx context.Context,
	msg *messages.Ingest,
	locationLimit int,
) ([]byte, *blackbird_entities.TopicBarrier, error) {
	start := time.Now()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	logging.Info(ctx, "beginning crawl")

	entries, err := o.gitClient.Diff(ctx, locationLimit, treeish(msg.ParentRepoID, msg.ParentCommitSHA), treeish(msg.RepoID, msg.CommitSHA))
	if err != nil {
		return nil, nil, err
	}

	filter, err := updateGeoFilter(msg.ParentGeometricXorFilter, entries)
	if err != nil {
		return nil, nil, err
	}

	size, err := geometricfilter.EstimateSize(filter)
	if err != nil {
		return nil, nil, err
	}
	logging.Info(ctx, "setting geo filter", kvp.Int("est_blob_locations", int(size)), kvp.Int("max_blob_locations", locationLimit))

	if size > float32(locationLimit) {
		return nil, nil, errTooManyBlobLocations
	}

	renewLease := func() error {
		host, err := o.indexerCluster.GetHost()
		if err != nil {
			return err
		}

		req := &indexpb.LeaseRequest{
			ShardId:       host.ShardID,
			EpochId:       uint32(msg.EpochID),
			ServingOffset: msg.ServingOffset,
			EntryId:       msg.EntryID,
			RepoId:        uint32(msg.RepoID),
		}

		leaseRes, err := host.Lease(ctx, req)
		if err != nil {
			if epochMovedErr := getNewEpochError(ctx, msg.EpochID, err); epochMovedErr != nil {
				return epochMovedErr
			}
			return err
		}

		msg.Lease.SetUnixMilli(int64(leaseRes.LeaseTimestamp))
		return nil
	}

	cacheRes, err := o.cachePublish(ctx, cancel, msg, entries, renewLease)
	if err != nil {
		logging.Error(ctx, "delta ingest cache published documents to blackbird but with errors", kvp.Err(err))
		return filter, topicBarrier(cacheRes), err
	}

	missingRes, err := o.cacheMissing(ctx, cancel, msg, entries.Filter(cacheRes.Missing), renewLease)
	tgr := mergeCacheResults(cacheRes, missingRes)

	if err != nil {
		logging.Error(ctx, "delta ingest cache published documents to blackbird but with errors", kvp.Err(err))
	} else {
		logging.Info(ctx, "delta ingest cache published documents to blackbird")
	}

	// NOTE: Defined to be equivalent to the metric used in IngestOp for dashboard continuity.
	statting.DistributionMs(ctx, "worker.ingest.delta_ingest.duration", time.Since(start))

	return filter, topicBarrier(tgr), err
}

func (o *IndexAPIIngestOp) cachePublish(
	ctx context.Context,
	cancel context.CancelFunc,
	msg *messages.Ingest,
	diff gitaccess.RepoDiff,
	renewLease crawl.RenewLease,
) (*crawl.TaskGroupResult, error) {
	tg := o.crawlPool.NewTaskGroup(ctx, cancel, renewLease)

	for _, change := range diff.BlobOIDChanges() {
		tg.EnqueueCachePublishTask(msg, change)
	}

	return tg.Wait()
}

func (o *IndexAPIIngestOp) cacheMissing(
	ctx context.Context,
	cancel context.CancelFunc,
	msg *messages.Ingest,
	diff gitaccess.RepoDiff,
	renewLease crawl.RenewLease,
) (*crawl.TaskGroupResult, error) {
	if diff.IsEmpty() {
		return &crawl.TaskGroupResult{PartitionOffsets: map[int32]int64{}}, nil
	}

	tg := o.crawlPool.NewTaskGroup(ctx, cancel, renewLease)

	// Fetch the content and send it to the analysis + publish task
	getBlobsErr := o.gitClient.GetBlobsForDiff(ctx, cancel, diff, func(blob *gitaccess.BlobContentChange) {
		tg.EnqueueCacheContentTask(msg, blob)
	})
	res, err := tg.Wait()

	// The error handling is a little tricky here because both GetBlobsForDiff and
	// the TaskGroup fan out to do concurrent work and can fail. Failure aborts
	// the entire ingest at this point. If GetBlobsForDiff fails it will cancel
	// `ctx` and the TaskGroup will abort. If a crawl task in the TaskGroup fails,
	// it will also cancel `ctx` and the GetBlobsForDiff fetches will abort.
	//
	// Pick the first non-nil, non-context cancelled error (if any)
	switch {
	case err == nil && getBlobsErr == nil:
		return res, nil
	case err != nil && !errors.Is(err, context.Canceled):
		logging.Error(ctx, "failed to publish for cache miss", kvp.Err(err))
		return res, err
	case getBlobsErr != nil && !errors.Is(getBlobsErr, context.Canceled):
		logging.Error(ctx, "failed to fetch content for diff for cache miss publishing", kvp.Err(getBlobsErr))
		return res, getBlobsErr
	default:
		// context cancelled due to deploy: return either error
		if err == nil && getBlobsErr != nil {
			err = getBlobsErr
		}
		return res, err
	}
}

func (o *IndexAPIIngestOp) newIngestMsg(t *Task, result *db.RepositoryResult) *messages.Ingest {
	repo := result.Repository

	ancestors := []types.RepoID{}
	for _, id := range t.event.BlackbirdAncestorRepoIds {
		ancestors = append(ancestors, types.RepoID(id))
	}

	return &messages.Ingest{
		Topic:               t.msg.Topic,
		Partition:           t.msg.Partition,
		Offset:              t.msg.Offset,
		HydroID:             t.envelope.Id,
		Change:              t.event.Change,
		RepoID:              repo.RepoID,
		OwnerID:             repo.OwnerID,
		NetworkID:           types.NetworkID(repo.NetworkID.Int32),
		OwnerLogin:          repo.OwnerLogin,
		RepoName:            repo.Name,
		IsPublic:            repo.IsPublic,
		IsArchived:          repo.IsArchived,
		IsFork:              repo.IsFork.Bool,
		RepoScore:           repo.RepoScore(),
		LicenseName:         repo.LicenseName,
		NumWatchers:         repo.NumWatchers.Int32,
		NumStars:            repo.NumStars.Int32,
		HasReadme:           repo.HasReadme.Bool,
		PublicForkCount:     repo.PublicForkCount.Int32,
		CommitSeqNo:         uint64(repo.CommitSeqNo.Int64),
		Head:                result.RefTip,
		PreallocatedChildID: t.event.BlackbirdSuggestedChildId,
		Ancestors:           ancestors,
		Corpus:              t.corpus.Corpus,
		EpochID:             t.corpus.EpochID,
		EpochMode:           o.indexerCluster.EpochMode(),
		DocumentTopic: routing.DocumentTopic{
			Corpus:     t.corpus.Corpus,
			EpochID:    t.corpus.EpochID,
			Partitions: o.topicConfig.Document.Partitions,
		},
		DotcomExperiments: repo.Experiments,
		IngestStartedAt:   time.Now().UTC(),
		RepoSeqNo:         types.RepoSeqNo(uint64(repo.RepoSeqNo.Int64)),
	}
}

func (o *IndexAPIIngestOp) newIngestMsgFromResponse(t *Task, res *indexpb.IndexResponse) *messages.Ingest {
	// NOTE: The response does not include enough information to know the ref name.
	head := &gitaccess.RefTip{CommitOID: gitaccess.NewObjectIDFromBytes(res.CommitSha)}

	return &messages.Ingest{
		Topic:                    t.msg.Topic,
		Partition:                t.msg.Partition,
		Offset:                   t.msg.Offset,
		HydroID:                  t.envelope.Id,
		RepoID:                   types.RepoID(res.RepoId),
		ParentRepoID:             types.RepoID(res.ParentRepoId),
		CommitSHA:                res.CommitSha,
		ParentCommitSHA:          res.ParentCommitSha,
		ParentGeometricXorFilter: res.ParentGeometricXorFilter,
		Head:                     head,
		Corpus:                   t.corpus.Corpus,
		EpochID:                  t.corpus.EpochID,
		EpochMode:                o.indexerCluster.EpochMode(),
		DocumentTopic: routing.DocumentTopic{
			Corpus:     t.corpus.Corpus,
			EpochID:    t.corpus.EpochID,
			Partitions: o.topicConfig.Document.Partitions,
		},
		EntryID:          res.EntryId,
		ParentEntryID:    res.ParentEntryId,
		CommitSeqNo:      res.CommitSeqNo,
		RepoSeqNo:        types.RepoSeqNo(res.RepoSeqNo),
		EntryExperiments: res.Experiments,
		IngestStartedAt:  time.Now().UTC(),
		SnapshotBarrier:  res.Barrier,
		Lease:            messages.NewLeaseFromUnixMilli(int64(res.LeaseTimestamp)),
		ServingOffset:    servingOffsetForIndexResponse(res),
	}
}

// shouldSkipPermanentError calls the GetPermanentError RPC until it gets a successful response.
func (o *IndexAPIIngestOp) shouldSkipPermanentError(ctx context.Context, t *Task) (*db.SkipReason, error) {
	// ADMIN_REPAIR events clear permanent errors, so we should never skip them.
	if t.event.Change == searchpb.RepositoryChanged_ADMIN_REPAIR {
		return nil, nil
	}

	attempt := 0
	var res *indexpb.GetPermanentErrorResponse
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Int("get_permanent_error_attempt", attempt), kvp.Err(err))
			return err
		}

		req := &indexpb.GetPermanentErrorRequest{
			ShardId: host.ShardID,
			EpochId: uint32(t.corpus.EpochID),
			RepoId:  uint32(t.repoID()),
		}

		gpeRes, err := host.GetPermanentError(ctx, req)
		if err != nil {
			logging.Error(ctx, "GetPermanentError RPC failed", kvp.Int("permanent_error_attempt", attempt), kvp.Err(err), kvp.String("index_host", host.Hostname))
			if epochMovedErr := getNewEpochError(ctx, t.corpus.EpochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}

			return err
		}

		res = gpeRes
		return nil
	}

	err := backoff.Retry(op, retry.Forever(ctx))
	if err != nil {
		return nil, err
	}

	if res.PermanentError == "" {
		return nil, nil
	}

	return &db.SkipPermanentError, nil
}

func treeish(repoID types.RepoID, oid []byte) *gitaccess.Treeish {
	if len(oid) == 0 {
		return nil
	}

	objectID := gitaccess.NewObjectIDFromBytes(oid)
	if objectID.IsNull() {
		return nil
	}

	return &gitaccess.Treeish{
		RepoID:  repoID,
		Treeish: spokes.NewTreeishWithObjectID(spokes.NewObjectID(objectID.String())),
	}
}

func servingOffsetForIndexResponse(res *indexpb.IndexResponse) int64 {
	if res.Barrier == nil {
		panic("invalid index response: no barrier")
	}

	if res.Barrier.TopicId != blackbird_entities.TopicBarrier_SNAPSHOT {
		panic("invalid index response: topic barrier is not for snapshot topic")
	}

	if len(res.Barrier.PartitionOffsets) != 1 {
		panic("invalid index response: topic barrier does not have a single partition offset")
	}

	return res.Barrier.PartitionOffsets[0].Offset
}

func updateGeoFilter(filter []byte, diff gitaccess.RepoDiff) ([]byte, error) {
	gitFiles := []geometricfilter.GitFile{}
	for _, entries := range diff {
		for _, entry := range entries {
			gitFiles = append(gitFiles, geometricfilter.GitFile{Path: entry.Path, BlobOID: entry.OID.Bytes()})
		}
	}

	return geometricfilter.ToggleFiles(filter, gitFiles)
}

func topicBarrier(tgr *crawl.TaskGroupResult) *blackbird_entities.TopicBarrier {
	if tgr == nil {
		return nil
	}

	barrier := &blackbird_entities.TopicBarrier{
		PartitionOffsets: []*blackbird_entities.TopicBarrier_PartitionOffset{},
		TopicId:          blackbird_entities.TopicBarrier_DOCUMENT,
	}

	for partition, offset := range tgr.PartitionOffsets {
		barrier.PartitionOffsets = append(barrier.PartitionOffsets, &blackbird_entities.TopicBarrier_PartitionOffset{Partition: partition, Offset: offset})
	}

	return barrier
}

func mergeCacheResults(a, b *crawl.TaskGroupResult) *crawl.TaskGroupResult {
	if a == nil && b == nil {
		return nil
	}

	if a == nil {
		return b
	}

	if b == nil {
		return a
	}

	out := &crawl.TaskGroupResult{
		PartitionOffsets: map[int32]int64{},
		NumDocs:          a.NumDocs + b.NumDocs,
		NumErrs:          a.NumErrs + b.NumErrs,
	}

	if a.MaxLogAppendTs.After(b.MaxLogAppendTs) {
		out.MaxLogAppendTs = a.MaxLogAppendTs
	} else {
		out.MaxLogAppendTs = b.MaxLogAppendTs
	}

	for partition, offset := range a.PartitionOffsets {
		out.PartitionOffsets[partition] = offset
	}

	for partition, offset := range b.PartitionOffsets {
		if out.PartitionOffsets[partition] < offset {
			out.PartitionOffsets[partition] = offset
		}
	}

	return out
}

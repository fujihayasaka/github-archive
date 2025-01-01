package consumers

import (
	"bytes"
	"context"
	"time"

	security_center_hydro_v1 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v1"

	"github.com/github/turboscan/ts/enabled_status"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/golang/protobuf/ptypes/timestamp"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
)

// RepoEventProcessor is responsible for processing and reacting to SecurityFeatureRepoUpdate messages.
// It implements the HydroProcessor interface.
type RepoEventProcessor struct {
	rs                   *repository.Service
	enabledStatusService *enabled_status.EnabledStatusService
	indexer              ts.Indexer
	alertService         *alert.Service
}

// Verify that AlertEventProcessor implements the HydroProcessor interface
var _ hydroProcessor = (*RepoEventProcessor)(nil)

func NewRepoEventProcessor(repoSvc *repository.Service, enabledStatusService *enabled_status.EnabledStatusService, alertService *alert.Service, indexer ts.Indexer) *RepoEventProcessor {

	return &RepoEventProcessor{
		rs:                   repoSvc,
		enabledStatusService: enabledStatusService,
		alertService:         alertService,
		indexer:              indexer,
	}
}

func (p *RepoEventProcessor) ProcessorName() string {
	return "RepoEventProcessor"
}

func (p *RepoEventProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {
	var msg security_center_hydro_v1.SecurityFeatureRepoUpdate
	if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
		return errors.Wrap(err, "unmarshalling repo event message")
	}
	msgTimestamp := envelope.GetTimestamp()
	startTime := time.Now()
	err := p.RepoUpdate(ctx, &msg, msgTimestamp)
	appctx.Logger(ctx).WithError(err).WithFields(
		kvp.String("gh.turboscan.msg_id", envelope.GetId()),
		ts.RepositoryEID(msg.Repository.Id).AsKVP(),
		kvp.Int("gh.org.id", int(msg.Repository.OrganizationId.Value)),
		kvp.Time("gh.turboscan.msg_timestamp", msgTimestamp.AsTime()),
		kvp.String("gh.turboscan.msg_source_event", msg.SourceEvent),
		kvp.String("gh.operation.name", "process_envelope"),
		kvp.Float64("gh.operation.duration", float64(time.Since(startTime))),
	).Info("processed SecurityFeatureRepoUpdate message")
	return err
}

func (p *RepoEventProcessor) RepoUpdate(ctx context.Context, msg *security_center_hydro_v1.SecurityFeatureRepoUpdate, msgTimestamp *timestamp.Timestamp) (err error) {
	// Archived and un-unarchived events come in pairs with GHAS toogle events
	// and can cause ES version conflicts because they are so close to each other.
	// Therefore we ignore the archive events as they have no effect on whether to show
	// code scanning alerts or not.
	if msg.SourceEvent == "repo.archived" || msg.SourceEvent == "repo.unarchived" {
		appctx.Stats(ctx).Counter("repositories.skipped", stats.Tags{"reason": "ignored_event"}, 1)
		appctx.With(ctx, kvp.String("gh.turboscan.action", "skip"), kvp.String("gh.turboscan.reason", "ignored_event"))
		return nil
	}
	repo, err := RepositoryFromProto(msg, msgTimestamp)
	if err != nil {
		return err
	}
	current, err := p.rs.Find(ctx, repo.RepositoryID)
	if err != nil {
		return err
	}

	if current != nil {
		if current.SourceUpdatedAt.Time.After(repo.SourceUpdatedAt.Time) {
			// the message we're processing is no longer relevant, so we can ignore it
			appctx.Stats(ctx).Counter("repositories.skipped", stats.Tags{"reason": "msg_timestamp"}, 1)
			appctx.With(ctx, kvp.String("gh.turboscan.action", "skip"), kvp.String("gh.turboscan.reason", "msg_timestamp"))
			return nil
		}
	}

	if current == nil {
		// If the repo is currently not known to us, we want to return early if
		// it also doesn't have an analysis. This way we only add it to the
		// repositories table if it is relevant to Code Scanning.
		filter := ts.AnalysisFilter{RepositoryID: repo.RepositoryID, IncludeDeleted: true, IncludeOutdated: true}
		analysis_exists, err := p.alertService.AnalysisExists(ctx, filter)
		if err != nil {
			return err
		}

		if !analysis_exists {
			// the update corresponds to an unknown repo for which we don't have any analyses, so we can ignore it
			appctx.Stats(ctx).Counter("repositories.skipped", stats.Tags{"reason": "no_analyses"}, 1)
			appctx.With(ctx, kvp.String("gh.turboscan.action", "skip"), kvp.String("gh.turboscan.reason", "no_analyses"))
			return nil
		}
	}
	appctx.Stats(ctx).Counter("repositories.updated", stats.Tags{}, 1)
	ctx = appctx.With(ctx, kvp.String("gh.turboscan.action", "update"))
	return p.update(ctx, current, repo)
}

func (p *RepoEventProcessor) update(ctx context.Context, current, incoming *ts.Repository) error {
	err := p.rs.Update(ctx, incoming)
	if err != nil {
		return err
	}

	if current == nil || !bytes.Equal(current.DefaultRef, incoming.DefaultRef) {
		// Renaming the default branch could constitute an enablement or disablement of Code Scanning.
		// If current is nil, that's like a special case of renaming.
		p.enabledStatusService.PublishStatusIfChanged(ctx, incoming.RepositoryID, ts.EnablementReason_DEFAULT_BRANCH_CHANGE, nil, nil)
		ctx = appctx.With(ctx, kvp.String("gh.turboscan.indexed", "repo_alerts"))
		return p.indexRepository(ctx, incoming)
	} else {
		// This is an optimization to avoid fetching and processing all alerts
		// when we only need to update ownership information or code scanning status.
		ctx = appctx.With(ctx, kvp.String("gh.turboscan.indexed", "repo_metadata"))
		return p.indexer.UpdateRepositoryMetadata(ctx, *incoming)
	}
}

// indexRepository indexes all alerts for the given repository.
func (p *RepoEventProcessor) indexRepository(ctx context.Context, repo *ts.Repository) error {

	loader := p.alertService.NewLoader(repo)
	loader.SetBatchSize(5000)
	return loader.BatchedLoad(ctx, func(alerts []*ts.LogicalAlert) error {
		docs, err := ts.SearchDocumentsFromAlerts(repo, alerts)
		if err != nil {
			return err
		}
		return p.indexer.IndexDocuments(ctx, ts.Index_OrgLevel, docs)
	})
}

func (p *RepoEventProcessor) Topics() []string {
	return []string{topics.RepoUpdate}
}

func (p *RepoEventProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	return handleError(ctx, err, m)
}

func (p *RepoEventProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: 0, RetryDelay: 0}
}

func (p *RepoEventProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}
func (p *RepoEventProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

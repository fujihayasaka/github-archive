package consumers

import (
	"context"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
	"google.golang.org/protobuf/proto"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/o11y"
)

type AlertLinkRefUpdater interface {
	CountAlertLinkByRef(ctx context.Context, repositoryID ts.RepositoryEID, ref ts.Ref) (uint64, error)
	UpdatePRFromRef(ctx context.Context, repositoryID ts.RepositoryEID, ref ts.Ref, pullRequestID ts.PullRequestEID) (int64, error)
}

// AlertLinkProcessor is responsible for processing and reacting to pr events and updating alert link rows.
// It implements the HydroProcessor interface.
type AlertLinkProcessor struct {
	alertLinkRefUpdater AlertLinkRefUpdater
}

// Verify that AlertLinkProcessor implements the HydroProcessor interface
var _ hydroProcessor = (*AlertLinkProcessor)(nil)

func NewAlertLinkProcessor(alertLinksService AlertLinkRefUpdater) *AlertLinkProcessor {
	return &AlertLinkProcessor{
		alertLinkRefUpdater: alertLinksService,
	}
}

func (p *AlertLinkProcessor) ProcessorName() string {
	return "AlertLinkProcessor"
}

func (p *AlertLinkProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {
	startTime := time.Now()

	var msg tshydro.PullRequestCreate
	if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
		return errors.Wrap(err, "unmarshalling pull request create message")
	}
	err := p.ProcessPullRequestCreate(ctx, &msg)

	duration := time.Since(startTime)
	skipped := errors.Is(err, ErrIgnoredEvent) || errors.Is(err, ErrDependabotEvent) || errors.Is(err, ErrForkedRepoEvent) || errors.Is(err, ErrNoMatchingAlertLinks)
	tags := stats.Tags{
		"success": strconv.FormatBool(err == nil || skipped),
		"skipped": strconv.FormatBool(skipped),
		"topic":   topic,
	}
	if skipped {
		tags["reason"] = errors.Cause(err).Error()
	}
	appctx.Stats(ctx).DistributionMs("alert_link_processor.message", tags, duration)
	if skipped {
		return nil
	}

	// Only log processed messages
	appctx.Logger(ctx).WithError(err).WithFields(
		kvp.String("gh.turboscan.msg_id", envelope.GetId()),
		ts.RepositoryEID(msg.Repository.Id).AsKVP(),
		kvp.String("gh.operation.name", "process_envelope"),
		kvp.Float64("gh.operation.duration", float64(duration)),
	).Info("processed alert link processor message")

	return err
}

func (p *AlertLinkProcessor) ProcessPullRequestCreate(ctx context.Context, msg *tshydro.PullRequestCreate) error {
	requestID := msg.GetRequestContext().GetRequestId()
	ctx = appctx.WithRequestID(ctx, requestID)
	ctx = requestid.WithGitHubRequestID(ctx, requestID)
	ctx = appctx.WithRepositoryID(ctx, uint64(msg.Repository.Id))

	ctx, span := o11y.StartSpan(ctx,
		oteltrace.WithAttributes(attribute.String("gh.request_id", requestID)),
		oteltrace.WithAttributes(attribute.Int("gh.repo.id", int(msg.Repository.Id))),
		oteltrace.WithAttributes(attribute.Int("gh.pull_request.id", int(msg.PullRequest.Id))),
		oteltrace.WithAttributes(attribute.Int("gh.pull_request.number", int(msg.Issue.Number))),
		oteltrace.WithAttributes(attribute.String("gh.pull_request.head_sha", msg.PullRequest.HeadSha)),
	)
	defer span.End()

	// Ignore events with no actor
	if msg.Actor == nil {
		return ErrIgnoredEvent
	}

	// Ignore Dependabot for now: PRs linked to alerts can only be created by users
	if msg.Actor.Login == "dependabot[bot]" {
		return ErrDependabotEvent
	}

	// Ignore events for forks for now: we'll only be processing refs that exist in the same repository
	if msg.Repository.Id != msg.HeadRepository.Id {
		return ErrForkedRepoEvent
	}

	pullRequestID := ts.PullRequestEID(msg.PullRequest.Id)
	repositoryID := ts.RepositoryEID(msg.Repository.Id)

	ref := append([]byte("refs/heads/"), msg.PullRequest.HeadBranch...)

	// We'll first check whether there are any alert links for this ref on the replica since this
	// processor will process a lot of events (all PRs) and we want to avoid unnecessary queries/writes
	// to the primary.
	count, err := p.alertLinkRefUpdater.CountAlertLinkByRef(gormext.WithTryReplica(ctx, true), repositoryID, ref)
	if err != nil {
		return errors.Wrap(err, "failed to count alert links")
	}

	if count == 0 {
		// If there are no alert links for this ref, we can skip the update
		return ErrNoMatchingAlertLinks
	}

	updatedLinksCount, err := p.alertLinkRefUpdater.UpdatePRFromRef(ctx, repositoryID, ref, pullRequestID)
	if err != nil {
		return errors.Wrap(err, "failed to update alert links")
	}

	appctx.Stats(ctx).Counter("alert_link_processor.updated_alert_links", stats.Tags{}, updatedLinksCount)

	return nil
}

func (p *AlertLinkProcessor) Topics() []string {
	return []string{topics.PullRequestCreate}
}

func (p *AlertLinkProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	return handleError(ctx, err, m)
}

func (p *AlertLinkProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: 0, RetryDelay: 0}
}

func (p *AlertLinkProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}

func (p *AlertLinkProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

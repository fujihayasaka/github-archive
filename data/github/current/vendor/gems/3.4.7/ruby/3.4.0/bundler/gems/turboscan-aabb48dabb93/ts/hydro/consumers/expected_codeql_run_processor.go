package consumers

import (
	"context"
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	cshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/hydro/topics"
	service "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/o11y"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	oteltrace "go.opentelemetry.io/otel/trace"
	"google.golang.org/protobuf/proto"
)

type CodeqlRunRetriever interface {
	GetCodeqlRunByShaAndRef(ctx context.Context, repoID ts.RepositoryEID, sha ts.Sha, ref ts.Ref) (*ts.CodeqlRun, error)
}

type ExpectedCodeqlRunProcessor struct {
	runRetriever CodeqlRunRetriever
	repoService  service.RepositoryDB
}

func NewExpectedCodeqlRunProcessor(ma CodeqlRunRetriever, repoService service.RepositoryDB) *ExpectedCodeqlRunProcessor {
	return &ExpectedCodeqlRunProcessor{
		runRetriever: ma,
		repoService:  repoService,
	}
}

func (p *ExpectedCodeqlRunProcessor) HandleError(ctx context.Context, err error, msg *hydro.Message) error {
	return handleError(ctx, err, msg)
}

func (p *ExpectedCodeqlRunProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {
	ctx, span := o11y.StartSpan(ctx, oteltrace.WithAttributes(attribute.String("gh.hydro.msg.envelope_id", envelope.Id)))
	defer span.End()
	start := time.Now()
	var err error
	var metric cshydro.ManagedAnalysesExpectedCodeqlRun
	if err = proto.Unmarshal(envelope.Message, &metric); err != nil {
		return errors.Wrap(err, "unmarshalling post receive event message")
	}
	if time.Since(metric.TriggeringEventTime.AsTime()) < time.Minute {
		<-time.After(time.Since(metric.TriggeringEventTime.AsTime()))
	}
	return p.processExpectedCodeqlRunEvent(ctx, &metric, &start, envelope)
}

func (p *ExpectedCodeqlRunProcessor) processExpectedCodeqlRunEvent(ctx context.Context, metric *cshydro.ManagedAnalysesExpectedCodeqlRun, start *time.Time, envelope *envelope.Envelope) (err error) {
	ctx, span := o11y.StartSpan(ctx,
		oteltrace.WithAttributes(attribute.Int("gh.repo.id", int(metric.RepositoryId))),
		oteltrace.WithAttributes((attribute.String("gh.commit.oid", metric.CommitOid))),
		oteltrace.WithAttributes((attribute.String("gh.git.ref", string(metric.Ref)))),
	)
	defer span.End()
	logMsg := "processed analysis trigger message"
	defer func() {
		duration := time.Since(*start)
		appctx.Logger(ctx).WithError(err).WithFields(
			kvp.String("gh.turboscan.msg_id", envelope.GetId()),
			kvp.String("gh.operation.name", "process_envelope"),
			kvp.Float64("gh.operation.duration", float64(duration)),
		).Error(logMsg)
	}()
	run, err := p.runRetriever.GetCodeqlRunByShaAndRef(ctx, ts.RepositoryEID(metric.RepositoryId), ts.ToSha(metric.CommitOid), ts.Ref(metric.Ref))
	if err != nil && !errors.Is(err, ts.ErrCodeqlRunNotFound) {
		logMsg = "run lookup failed"
		return err
	}

	appctx.Stats(ctx).Counter("code_scanning.managed_analyses.run_triggered.slo", stats.Tags{
		"success":        fmt.Sprintf("%t", run != nil),
		"default_branch": fmt.Sprintf("%t", metric.DefaultBranch),
		"trigger":        triggerEventTypeSloTag(metric.TriggeringEventType),
	}, 1)
	return nil
}

func triggerEventTypeSloTag(eventType string) string {
	switch eventType {
	case "pull_request_synchronize", "pull_request_create":
		return "pr"
	case "post_receive":
		return "push"
	default:
		return eventType
	}
}

func (p *ExpectedCodeqlRunProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: 0, RetryDelay: 0}
}

func (p *ExpectedCodeqlRunProcessor) Topics() []string {
	return []string{topics.ManagedAnalysesExpectedCodeqlRun}
}

func (p *ExpectedCodeqlRunProcessor) BeforeRetry(ctx context.Context, err error, count int, envelope *envelope.Envelope, msg *hydro.Message) {
}

func (p *ExpectedCodeqlRunProcessor) OnPermanentFailure(ctx context.Context, envelope *envelope.Envelope, msg *hydro.Message) error {
	return nil
}

func (p *ExpectedCodeqlRunProcessor) ProcessorName() string {
	return "ExpectedCodeqlRunProcessor"
}

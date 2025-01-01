package consumers

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	actionschemas "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	hydro_schemas_github_v1_entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
)

type WorkflowEventProcessor struct {
	aqueduct aqueduct.JobPerformer
}

var _ hydroProcessor = (*WorkflowEventProcessor)(nil)

func NewWorkflowEventProcessor(aqueduct aqueduct.JobPerformer) *WorkflowEventProcessor {

	return &WorkflowEventProcessor{
		aqueduct: aqueduct,
	}
}

func (p *WorkflowEventProcessor) ProcessorName() string {
	return "WorkflowEventProcessor"
}

func (p *WorkflowEventProcessor) ProcessEnvelope(ctx context.Context, envelope *envelope.Envelope, topic string) error {
	var msg actionschemas.WorkflowExecution

	if err := proto.Unmarshal(envelope.Message, &msg); err != nil {
		return errors.Wrap(err, "unmarshalling WorkflowExecution message")
	}

	return p.processMessage(ctx, &msg)
}

func (p *WorkflowEventProcessor) processMessage(ctx context.Context, msg *actionschemas.WorkflowExecution) error {
	if msg.GetWorkflowFilePath() == ts.ManagedAnalysisWorkflowPath {
		appctx.Logger(ctx).Info("workflow event", kvp.String("gh.actions.workflow.path", msg.GetWorkflowFilePath()), ts.RepositoryEID(msg.GetWorkflowRepositoryId()).AsKVP())

		conclusion := ts.CodeqlRunStatus_FAILED
		if msg.CheckSuiteConclusion == hydro_schemas_github_v1_entities.CheckSuiteConclusion_SUCCESS {
			conclusion = ts.CodeqlRunStatus_COMPLETED
		}

		job := jobs.SetDynamicRunConclusion{
			RepositoryID:  ts.RepositoryEID(msg.WorkflowRepositoryId),
			OwnerID:       ts.OwnerEID(msg.WorkflowRepositoryOwnerId),
			WorkflowRunID: ts.WorkflowRunEID(msg.WorkflowRunId),
			Sha:           ts.ToSha(msg.WorkflowRepositorySha),
			Conclusion:    conclusion,
		}
		_, err := p.aqueduct.PerformLater(ctx, job)
		if err != nil {
			return err
		}

		appctx.Stats(ctx).Counter("workflow_event_processor.status", stats.Tags{"success": "true"}, 1)
	}

	return nil
}

func (p *WorkflowEventProcessor) Topics() []string {
	return []string{topics.WorkflowExecution}
}

func (p *WorkflowEventProcessor) HandleError(ctx context.Context, err error, m *hydro.Message) error {
	appctx.Stats(ctx).Counter("workflow_event_processor.status", stats.Tags{"success": "false"}, 1)
	return handleError(ctx, err, m)
}

func (p *WorkflowEventProcessor) GetRetryPolicy() RetryPolicy {
	return RetryPolicy{MaxRetryElapsedTime: 0, RetryDelay: 0}
}

func (p *WorkflowEventProcessor) BeforeRetry(ctx context.Context, lastErr error, errCnt int, e *envelope.Envelope, m *hydro.Message) {
}

func (p *WorkflowEventProcessor) OnPermanentFailure(ctx context.Context, e *envelope.Envelope, m *hydro.Message) error {
	return nil
}

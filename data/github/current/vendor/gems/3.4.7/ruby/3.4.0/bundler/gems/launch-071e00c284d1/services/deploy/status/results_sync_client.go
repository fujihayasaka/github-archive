package status

import (
	"context"

	eventsv1 "github.com/github/actions-proto/gen/go/results/events/v1"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/types"

	"github.com/github/launch/observability/ctxstash"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	proto "google.golang.org/protobuf/proto"

	"github.com/github/launch/clients/aqueduct"
)

// resultsSyncClient handles data synchronization between launch and the results service
type resultsSyncClient struct {
	aqueductClient    aqueduct.Client
	resultsApp        string
	log               logs
	githubTwirpClient ghtwirp.Client
}

var _ syncClient = (*resultsSyncClient)(nil)

const (
	actionsSyncEventsQueue         = "actions-sync-events"
	workflowJobRunCreateEvent      = "workflow-job-run-create"
	workflowJobRunCreateEventProto = "actionsproto:workflow-job-run-create"
)

func newResultsSyncClient(aqueductClient aqueduct.Client, log logs, githubTwirpClient ghtwirp.Client) *resultsSyncClient {
	return &resultsSyncClient{
		aqueductClient:    aqueductClient,
		resultsApp:        "actions-results-production",
		log:               log,
		githubTwirpClient: githubTwirpClient,
	}
}

func (client *resultsSyncClient) CreateCheckRun(ctx context.Context, workflowRunBackendID string, workflowJobRunBackendID string, repoID types.GlobalID, displayName string, checkRunDatabaseID int64) error {
	var payload []byte
	var err error
	var aqueductEventHeader string
	createdWorkflowJobRunProto := &eventsv1.WorkflowJobRunCreate{
		WorkflowJobRunBackendId: workflowJobRunBackendID,
		WorkflowRunBackendId:    workflowRunBackendID,
		RepositoryGlobalId:      repoID.String(),
		Name:                    displayName,
		CheckRunDatabaseId:      checkRunDatabaseID,
	}

	payload, err = proto.Marshal(createdWorkflowJobRunProto)
	if err != nil {
		return errors.Wrap(err, "unable to marshal actions proto workflow job run creation payload")
	}

	aqueductEventHeader = workflowJobRunCreateEventProto

	jobID, err := client.aqueductClient.Send(ctx, aqueduct.Job{
		App:     client.resultsApp,
		Queue:   actionsSyncEventsQueue,
		Payload: payload,
		Headers: map[string]string{
			actionsResultsEventHeader:    aqueductEventHeader,
			results.RequestIDHeader:      ctxstash.From(ctx).Correlations().GitHub.RequestID,
			ctxstash.VSSCorrelationIDKey: ctxstash.From(ctx).Correlations().VSS.CorrelationID,
		},
	}, statusAqueductOptions...)

	client.log.Debug(ctx, "results events message sent to aqueduct",
		kvp.String("gh.aqueduct.app", client.resultsApp),
		kvp.String("gh.aqueduct.queue.name", actionsResultsEventsQueue),
		kvp.String("gh.aqueduct.job.id", jobID))

	if err != nil {
		return err
	}
	return nil
}

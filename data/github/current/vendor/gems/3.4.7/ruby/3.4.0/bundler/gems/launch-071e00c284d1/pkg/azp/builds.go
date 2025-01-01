package azp

import (
	"context"
	"encoding/base64"
	"strings"
	"time"

	errs "github.com/pkg/errors"

	runservice "github.com/github/actions-proto/gen/go/run-service/api/twirp/v1"
	parser "github.com/github/actions-workflow-parser/go"

	"github.com/github/launch/clients/utils"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/receiver"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/requiredworkflowutils"
	"github.com/github/launch/workflowbuild/build"
)

// AZP API.
// See: https://docs.microsoft.com/en-us/rest/api/azure/devops/build/builds?view=azure-devops-rest-5.0
type BuildsClient interface {
	GetRunTenantInfo() *runservice.TenantInfo
	Queue(ctx context.Context, wfb *build.WorkflowBuild, receiverURL string, resultsReceiverURL string, secretSource string, secretsUnencrypted map[string]string, variables map[string]string, wft *parser.WorkflowTemplate, concurrency *parser.ConcurrencySetting, featureFlags map[string]bool, appEnv launchconfig.AppEnv) (*Build, error)
	RunInfo(ctx context.Context, id types.WorkflowExecutionID) (*RunInfoResponse, error)
	Cancel(ctx context.Context, workflowRunID string, opts *CancelOptions) error
	DeleteLogs(ctx context.Context, workflowRunID string) error
	DeleteLogsByPlanID(ctx context.Context, planID string) error
	ReportAdminEvent(ctx context.Context, name string, data map[string]string) error
}

// Build is a build from within a pipeline.
type Build struct {
	ID    int    `json:"id"`
	State string `json:"state"`
}

func buildBillingPlanOwnerPayload(actionsBillingPlanOwner build.ActionsBillingPlanOwner) rootPayloadBillingPlanOwner {
	payload := rootPayloadBillingPlanOwner{
		ID:         actionsBillingPlanOwner.ID.String(),
		DatabaseID: actionsBillingPlanOwner.DatabaseID,
		Name:       actionsBillingPlanOwner.Name,
		PlanSku:    actionsBillingPlanOwner.PlanSKU,
		Type:       actionsBillingPlanOwner.Type,
		TenantID:   actionsBillingPlanOwner.TenantID,
		TenantName: actionsBillingPlanOwner.TenantName,
	}

	// OrganizationTenantName is only used when PlanOwner is a Business (aka Enterprise account)
	if actionsBillingPlanOwner.Type == "Business" {
		// We know that RepositoryOwner is an Organization, because PlanOwner is a business
		payload.OrganizationID = actionsBillingPlanOwner.RepositoryOwnerID.String()
		payload.OrganizationTenantID = actionsBillingPlanOwner.OrganizationTenantID
		payload.OrganizationTenantName = actionsBillingPlanOwner.OrganizationTenantName
	}

	return payload
}

func isScheduledEvent(eventName string) bool {
	return eventName == flowevents.ScheduleEventName
}

func NewBuildPayload(
	wfb *build.WorkflowBuild,
	receiverURL string,
	resultsReceiverURL string,
	secretSource string,
	secretsUnencrypted map[string]string,
	variables map[string]string,
	wft *parser.WorkflowTemplate,
	concurrency *parser.ConcurrencySetting,
	featureFlags map[string]bool,
	appEnv launchconfig.AppEnv,
) (*MultipartPayload, error) {
	jobStatusCallbackURL, err := receiver.GetJobStatusCallbackURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build job callback url")
	}

	runStatusCallbackURL, err := receiver.GetRunStatusCallbackURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build run callback url")
	}

	gateStatusCallbackURL, err := receiver.GetGateStatusCallbackURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build gate callback url")
	}

	environmentCallbackURL, err := receiver.GetEnvironmentCallbackURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build get environment url")
	}

	preJobURL, err := receiver.GetPreJobRequestURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build prejob request url")
	}

	tokenRefreshURL, err := receiver.GetTokenRefreshURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build token refresh url")
	}

	tokenRevokeURL, err := receiver.GetTokenRevokeURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build token revoke url")
	}

	actionResolutionURL, err := receiver.GetActionResolutionURL(receiverURL, wfb.SigningKey.WorkflowID, wfb.SigningKey.Timestamp)
	if err != nil {
		return nil, errs.Wrap(err, "failed to build action resolution url")
	}

	eventPayload, err := flowevents.WorkflowEventPayload(wfb.Event, wfb.EventPayload)
	if err != nil {
		return nil, errs.Wrap(err, "error decoding event for use in build payload")
	}

	// This will overwrite the slug in the results receiver URL in multitenant mode, otherwise it will be a no-op
	resultsReceiverURL, err = utils.FormatTenantURL(resultsReceiverURL, wfb.GitHubTenant.Slug)
	if err != nil {
		return nil, errs.Wrap(err, "unable to format results receiver url")
	}

	referencedFiles := make(map[string]rootPayloadReferencedFile, len(wfb.ReferencedFiles))
	for path, rf := range wfb.ReferencedFiles {
		referencedFiles[path] = rootPayloadReferencedFile{
			TenantID:             rf.TenantID,
			Ref:                  rf.Ref,
			SHA:                  rf.SHA,
			Repository:           rf.RepositoryNWO.String(),
			RepositoryID:         rf.RepositoryID,
			RepositoryDatabaseID: rf.RepositoryDatabaseID,
			IsTrusted:            rf.IsTrusted,
			PlanOwnerID:          rf.PlanOwnerID,
		}
	}

	refType := "branch"
	if wfb.CheckoutRef.IsTagRef() {
		refType = "tag"
	}

	buildPayload := &BuildPayload{
		Root: RootPayload{
			PlanID: wfb.ExecutionID.String(),
			Configuration: rootPayloadConfig{
				MainFilePath: requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(wfb.WorkflowFilePath),
				Callbacks: rootPayloadCallbacks{
					JobStatusURL:        jobStatusCallbackURL,
					RunStatusURL:        runStatusCallbackURL,
					GateStatusURL:       gateStatusCallbackURL,
					EnvironmentURL:      environmentCallbackURL,
					PreJobURL:           preJobURL,
					TokenRefreshURL:     tokenRefreshURL,
					TokenRevokeURL:      tokenRevokeURL,
					ActionResolutionURL: actionResolutionURL,
					// The Runner will use the base URL to build calls to Launch in four-nines
					ReceiverURL:        receiverURL,
					ResultsReceiverURL: resultsReceiverURL,
					SignatureKey:       base64.StdEncoding.EncodeToString(wfb.SigningKey.Key),
				},
				ReferencedFiles: referencedFiles,
				OidcConfig: oidcConfig{
					SubClaimCustomizationTemplate: wfb.RunEnvironment.OidcSubClaimCustomizationTemplate,
					CustomizeEnterpriseIssuer:     wfb.RunEnvironment.CustomizeEnterpriseOidcIssuer,
				},
				RootWorkflow: rootWorkflow{
					FilePath:           requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(wfb.RootWorkflow.FilePath),
					Ref:                wfb.RootWorkflow.Ref,
					SHA:                wfb.RootWorkflow.SHA,
					Repository:         wfb.RootWorkflow.Repository,
					RepositoryID:       wfb.RootWorkflow.RepositoryID,
					IsRequiredWorkflow: wfb.RootWorkflow.IsRequiredWorkflow,
				},
				IsLab: appEnv.IsLab(),
			},
			Context: rootPayloadContext{
				Repository:                        wfb.RunEnvironment.Repository.String(),
				RepositoryName:                    wfb.RunEnvironment.Repository.Name,
				RepositoryOwner:                   wfb.RunEnvironment.Repository.Owner,
				RepositoryURL:                     wfb.RunEnvironment.GitURL,
				PrivateRepository:                 wfb.RunEnvironment.PrivateRepository,
				ForkedRepository:                  wfb.RunEnvironment.ForkedRepository,
				RepositoryVisibility:              wfb.RunEnvironment.RepositoryVisibility,
				Actor:                             wfb.RunEnvironment.ExecutingActor,
				ActorID:                           wfb.RunEnvironment.ExecutingActorID,
				ActorDatabaseID:                   wfb.RunEnvironment.ExecutingActorDatabaseID,
				ForkedPullRequest:                 wfb.RunEnvironment.ForkedPullRequest,
				ParentRepositoryName:              wfb.RunEnvironment.ParentRepository.Name,
				RepoSelfHostedRunnersDisabled:     wfb.RunEnvironment.SelfHostedRunnersDisabled,
				ParentRepositoryOwner:             wfb.RunEnvironment.ParentRepository.Owner,
				OwnerID:                           wfb.RunEnvironment.OwnerID.String(),
				OwnerDatabaseID:                   wfb.RunEnvironment.OwnerDatabaseID,
				OwnerCreatedAt:                    wfb.RunEnvironment.OwnerCreatedAt,
				EnterpriseManagedBusinessID:       wfb.RunEnvironment.EnterpriseManagedBusinessID,
				RepositoryID:                      wfb.RunEnvironment.RepositoryID,
				RepositoryDatabaseID:              wfb.RunEnvironment.RepositoryDatabaseID,
				RunID:                             wfb.RunEnvironment.WorkflowRunID,
				RunNumber:                         wfb.RunEnvironment.WorkflowRunNumber,
				RunAttempt:                        wfb.RunEnvironment.WorkflowRunAttempt,
				Sha:                               wfb.CheckoutSHA.String(),
				Ref:                               wfb.CheckoutRef.String(),
				RetentionDays:                     wfb.RunEnvironment.RetentionDays,
				ActionsCacheSizeLimit:             wfb.RunEnvironment.ActionsCacheSizeLimit,
				OidcSubClaimCustomizationTemplate: wfb.RunEnvironment.OidcSubClaimCustomizationTemplate,
				RepositoryTier:                    int64(wfb.RunEnvironment.RepositoryTier),
				WorkflowPermissionsPolicy:         NewWorkflowPermissionPolicy(wfb.RunEnvironment.DefaultWorkflowPermissions),
				BillingPlanOwner:                  buildBillingPlanOwnerPayload(wfb.ActionsBillingPlanOwner),
				ExtendedContext: rootPayloadExtendedContext{
					Actor:           wfb.RunEnvironment.ExecutingActor,
					TriggeringActor: wfb.RunEnvironment.TriggeringActor,
					Workflow:        wfb.RunEnvironment.Workflow,
					HeadRef:         wfb.RunEnvironment.HeadRef.String(),
					BaseRef:         wfb.RunEnvironment.BaseRef.String(),
					EventName:       wfb.RunEnvironment.Event,
					Event:           eventPayload,
					ServerURL:       strings.TrimSuffix(wfb.RunEnvironment.ServerURL, "/"),
					APIURL:          strings.TrimSuffix(wfb.RunEnvironment.APIURL, "/"),
					GraphQLURL:      strings.TrimSuffix(wfb.RunEnvironment.GraphQLURL, "/"),
					RefName:         wfb.CheckoutRef.TrimRefPrefix(),
					RefProtected:    wfb.CheckoutRefProtected,
					RefType:         refType,
					SecretSource:    secretSource,
				},
				RunFeatureFlagsContext: featureFlags,
				GitHubTenantSlug:       wfb.GitHubTenant.Slug,
			},
			Secrets:          secretsUnencrypted,
			Variables:        variables,
			WorkflowTemplate: wft,
			Concurrency:      concurrency,
		},
	}

	if wfb.RerunInfo != nil {
		buildPayload.Root.RerunContext = &rerunContext{
			PreviousPlanID: wfb.RerunInfo.PlanID,
			JobIDs:         wfb.RerunInfo.JobIDs,
		}
	}

	// wfb.AbuseContext will always be nil if running in enterprise mode
	if wfb.AbuseContext != nil {
		buildPayload.Root.Context.GitHubEventInfo = &gitHubEventInfo{
			AbuseInfo:     wfb.AbuseContext,
			IsScheduled:   isScheduledEvent(wfb.Event),
			CustomerLabel: wfb.CustomerLabel,
		}
	}

	if wfb.RunEnvironment.ForkedPullRequest {
		buildPayload.Root.Context.ForkedPullRequestEventContext = forkPullRequestEventContext{
			HeadRepository:        wfb.RunEnvironment.HeadRepository.String(),
			HeadRepositoryID:      wfb.RunEnvironment.HeadRepositoryID,
			HeadRepositoryName:    wfb.RunEnvironment.HeadRepository.Name,
			HeadRepositoryOwner:   wfb.RunEnvironment.HeadRepository.Owner,
			HeadRepositoryOwnerID: wfb.RunEnvironment.HeadRepositoryOwnerID,
		}
	}

	buildPayload.Files = make([]FilePayload, 0, len(wfb.ResolvedFiles))
	for _, file := range wfb.ResolvedFiles {
		buildPayload.Files = append(buildPayload.Files, FilePayload{
			Path:    requiredworkflowutils.RemoveMetadataFromRequiredWorkflowPath(file.Path),
			Content: []byte(file.Text),
		})
	}

	payload, err := buildPayload.ToMultipartPayload()
	if err != nil {
		return nil, errs.Wrap(err, "unable to create multi-part payload")
	}

	return payload, nil
}

type CancelOptions struct {
	ActorName *string
	Force     bool
}

type RunInfoResponse struct {
	Status              string     `json:"status"`
	Conclusion          string     `json:"conclusion"`
	StartedAt           *time.Time `json:"started_at"`
	CompletedAt         *time.Time `json:"completed_at"`
	HasPendingGate      bool       `json:"has_pending_gate"`
	IsWaitingOnResource bool       `json:"is_waiting_on_resource"`
}

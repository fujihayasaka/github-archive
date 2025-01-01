package status

import (
	"context"
	"time"

	"github.com/github/go-kvp"
	errs "github.com/pkg/errors"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
)

// graphQLStatusClient handles status updates over graphql to dotcom
type graphQLStatusClient struct {
	logger          logs
	stats           statter.Statter
	labLogger       logs
	clientConfig    clientConfig
	repoOwnerClient github.Client
	repoClient      github.Client
	isMultitenant   bool
}

type clientConfig struct {
	repoConfig    *repoConfig
	ghFactory     github.Factory
	ghTwirpClient ghtwirp.Client
}

type repoConfig struct {
	workflowID string
	buildRepo  deployer.WorkflowBuildsRepository
}

var _ syncStatusClient = (*graphQLStatusClient)(nil)
var _ statusClient = (*graphQLStatusClient)(nil)

func newGraphQLStatusClient(logger, labLogger logs, config clientConfig, stats statter.Statter, isMultitenant bool) *graphQLStatusClient {
	return &graphQLStatusClient{logger: logger, labLogger: labLogger, clientConfig: config, stats: stats, isMultitenant: isMultitenant}
}

func (gqc *graphQLStatusClient) initRepositoryOwnerClient(ctx context.Context, repoID, ownerID types.GlobalID) error {
	if gqc.repoOwnerClient != nil {
		return nil
	}

	ghClient, err := gqc.clientConfig.ghFactory.NewClientForRepositoryOwner(ctx, repoID, ownerID)
	if err != nil {
		return errs.Wrap(err, "unable to create new client")
	}

	gqc.repoOwnerClient = ghClient
	return nil
}

func (gqc *graphQLStatusClient) initRepositoryClient(ctx context.Context) error {
	if gqc.repoClient != nil {
		return nil
	}

	if gqc.clientConfig.repoConfig == nil {
		return errs.New("unable to provision repo client")
	}

	buildState, ok, err := gqc.clientConfig.repoConfig.buildRepo.GetDataForTokenRequest(ctx, gqc.clientConfig.repoConfig.workflowID)
	if err != nil {
		return errs.Wrap(err, "unable to query build state")
	}
	if !ok {
		return svcerr.NewNotFoundError("no token request data for this workflow")
	}

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if gqc.isMultitenant {

		if buildState.GitHubTenantID == nil {
			return errs.New("GitHub tenant id in workflow build state must not be nil")
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *buildState.GitHubTenantID, gqc.isMultitenant)
		if err != nil {
			return errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state")
		}
	}

	// If user default the token to all read, the check run will not even get created at all.
	// Notice it's still an internal service call, we should make sure we can create the check run, thus set check permission to write directly.
	permissions := tokens.InstallationPermissions{
		Checks: tokens.WriteAccess,
		// Access to deployments access needs to match the permissions of the build it's running in. If the run doesn't have
		// deployment access (e.g. fork PR), this token shouldn't be able to create deployments.
		// More context: https://github.com/github/launch/pull/3778
		Deployments: buildState.TokenPermissions.Deployments,
	}

	repoOwner := buildState.WorkflowMetadata.RepositoryOwner
	var ownerID types.GlobalID
	if repoOwner != nil {
		ownerID = types.NewGlobalID(ctx, repoOwner.GlobalRelayID)
	} else {
		ownerID = types.NilGlobalID
	}

	ghClient, err := gqc.clientConfig.ghFactory.NewClientForRepository(ctx, buildState.RepositoryID, ownerID, &github.ClientTokenOptions{
		UseTokenCache:    true,
		TokenPermissions: &permissions,
	})

	if err != nil {
		return errs.Wrap(err, "unable to create new client")
	}

	gqc.repoClient = ghClient
	return nil
}

func (gqc *graphQLStatusClient) UpdateGateStatus(ctx context.Context, req *GateStatusRequest, params UpdateGateStatusParams) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if err := gqc.initRepositoryOwnerClient(ctx, params.RepositoryID, params.OwnerID); err != nil {
		return errs.Wrap(err, "unable to build client")
	}

	state := closed
	if req.GetIsOpen() {
		state = open
	}

	var expiresAt time.Time
	if req.Deadline != nil {
		expiresAt = req.Deadline.AsTime()
	}

	greq := github.CreateGateRequestRequest{
		GateID:     types.NewGlobalID(ctx, req.GetGateId()),
		CheckRunID: params.CheckRunID,
		State:      state.String(),
		Token:      req.GetToken(),
		Concluded:  req.IsConcluded,
		ExpiresAt:  expiresAt,
	}

	_, err := gqc.repoOwnerClient.CreateGateRequest(ctx, greq)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "unable to update gate status"))
	}

	return nil
}

func (gqc *graphQLStatusClient) UpdateCheckSuite(ctx context.Context, req *RunStatusRequest, params UpdateCheckSuiteParams) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if err := gqc.initRepositoryClient(ctx); err != nil {
		return errs.Wrap(err, "unable to build client")
	}

	// build graphql check suite mutation
	checkSuiteRequest, err := buildUpdateCheckSuiteGraphQL(ctx, gqc.logger, req, params.CheckSuiteState, params.WaitingOn)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "could not build update check suite request"))
	}
	gqc.labLogger.Log(ctx, "debugging update check suite request", kvp.Any("gh.launch.check_suite.request", checkSuiteRequest))

	// check if new mutation annotations != original request annotations
	runComplete := req.GetComplete()
	if runComplete != nil {
		ctx := ctxstash.WithFields(ctx,
			kvp.Int("gh.launch.annotation_count", len(req.GetAnnotations())),
		)

		if len(req.GetAnnotations()) != len(checkSuiteRequest.Annotations) {
			gqc.logger.Report(
				ctx,
				errs.New("incoming annotation count does not match check suite annotation count"),
				kvp.Int("gh.launch.incoming_annotation.count", len(req.GetAnnotations())),
				kvp.Int("gh.launch.outgoing_annotation.count", len(checkSuiteRequest.Annotations)),
				kvp.String("gh.launch.workflow.identifier", params.CheckSuiteState.WorkflowFilePath),
			)
		}
	}

	// update dotcom via graphql mutation
	res, err := gqc.repoClient.UpdateCheckSuite(ctx, *checkSuiteRequest)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "unable to update check suite"))
	}
	if res == nil {
		return tracing.RecordError(span, errs.New("ID pair not found in output"))
	}

	return nil
}

func buildUpdateCheckSuiteGraphQL(ctx context.Context, logger logs, update *RunStatusRequest, checkSuiteState *types.CheckSuiteState, waitingOn *WaitingOn) (*github.UpdateCheckSuiteRequest, error) {
	artifacts := make([]*github.CheckRunArtifact, 0, len(update.Artifacts))

	for _, artifact := range update.Artifacts {
		createdAt := artifact.GetCreatedAt().AsTime()

		var expiresAt time.Time
		if artifact.GetExpiresAt() != nil {
			expiresAt = artifact.GetExpiresAt().AsTime()
		}

		artifacts = append(artifacts, &github.CheckRunArtifact{
			SourceURL: artifact.GetUrl(),
			Name:      artifact.GetName(),
			Size:      artifact.GetSize(),
			ExpiresAt: getArtifactExpiration(createdAt, expiresAt),
			CreatedAt: &createdAt,
		})
	}

	isCompleted := update.GetComplete() != nil
	isValid, conclusion := mapConclusionGraphQL(update)

	if !isValid {
		logger.Report(ctx, errs.Errorf("Unknown conclusion %q", conclusion))
	}

	checkSuiteRequest := &github.UpdateCheckSuiteRequest{
		RepositoryID: checkSuiteState.RepositoryID,
		CheckSuiteID: checkSuiteState.CheckSuiteIDPair.GlobalID,
		// note: update this if in future we receive run postbacks for non-complete states
		CompletedLogURL: update.GetCompletedLog().GetUrl(),
		Artifacts:       artifacts,
		Conclusion:      string(conclusion),
	}

	if update.Concurrency != nil {
		checkSuiteRequest.Concurrency = &github.Concurrency{
			Group: update.Concurrency.Group,
		}
		if update.Concurrency.WaitingOnResource != nil && waitingOn != nil {
			checkSuiteRequest.Concurrency.WaitingOnResource = &github.WaitingOnResource{
				CheckSuiteID: waitingOn.CheckSuiteID,
				CheckRunID:   waitingOn.CheckRunID,
				Identifier:   update.Concurrency.WaitingOnResource.Identifier,
			}
		}
	}

	if isCompleted && len(update.Annotations) > 0 {
		csas, err := getRunPostbackAnnotationsGraphQL(update)
		if err != nil {
			return nil, errs.Wrap(err, "could not build run postback annotations")
		}
		checkSuiteRequest.Annotations = csas
	}

	return checkSuiteRequest, nil
}

func getRunPostbackAnnotationsGraphQL(req *RunStatusRequest) ([]github.CheckSuiteAnnotation, error) {
	csas := make([]github.CheckSuiteAnnotation, 0, len(req.Annotations))
	for _, ann := range req.Annotations {

		name, err := getAnnotationLevelName(ann.AnnotationLevel)
		if err != nil {
			return csas, errs.Wrap(err, "unable to determine a valid annotation level name")
		}

		csa := github.CheckSuiteAnnotation{
			AnnotationLevel: name,
			Message:         ann.GetMessage(),
			RawDetails:      ann.GetRawDetails(),
			Path:            ann.GetPath(),
			Title:           ann.GetTitle(),
			Location:        getAnnotationRangeGraphQL(ann),
		}

		csas = append(csas, csa)
	}
	return csas, nil
}

// mapConclusionGraphQL returns if the conclusion is a valid mapping and the corresponding graphql conclusion type
func mapConclusionGraphQL(update *RunStatusRequest) (bool, github.CheckSuiteConclusion) {
	completed := update.GetComplete()
	if completed == nil {
		return true, ""
	}

	conclusion := completed.GetConclusion()

	switch conclusion {
	case RunConclusion_SUCCEEDED:
		return true, github.CheckSuiteSuccessConclusion
	case RunConclusion_CANCELED:
		return true, github.CheckSuiteCancelledConclusion
	case RunConclusion_FAILED:
		return true, github.CheckSuiteFailureConclusion
	case RunConclusion_SKIPPED:
		return true, github.CheckSuiteSkippedConclusion
	case RunConclusion_NOT_PROVIDED:
		return true, ""
	default:
		return false, ""
	}
}

func (gqc *graphQLStatusClient) CreateCheckRun(ctx context.Context, req *JobStatusRequest, params CreateCheckRunParams) (*types.IDPair, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if err := gqc.initRepositoryClient(ctx); err != nil {
		return nil, errs.Wrap(err, "unable to build client")
	}

	// build create run graphql mutation
	checkRunRequest, err := buildCreateCheckRunGraphQL(req, params.CheckSuiteState, params.WaitingOn)
	if err != nil {
		return nil, tracing.RecordError(span, errs.Wrap(err, "Error generating check run request"))
	}
	gqc.labLogger.Debug(ctx, "debugging create check run request", kvp.Any("gh.launch.check_suite.request", checkRunRequest))

	// update dotcom via graphql mutation
	res, err := gqc.repoClient.CreateCheckRun(ctx, *checkRunRequest)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}
	if res.CheckRunIDPair.IsZeroValue() {
		return nil, tracing.RecordError(span, errs.New("CheckRunIDPair not found in output"))
	}
	gqc.logger.Log(ctx, "created check run",
		kvp.String("gh.check_run.global_id", res.CheckRunIDPair.GlobalID.String()),
		kvp.Int("gh.check_run.id", int(res.CheckRunIDPair.DatabaseID)),
		kvp.String("gh.check_run.status", checkRunRequest.Status),
	)
	return &res.CheckRunIDPair, nil
}

func (gqc *graphQLStatusClient) UpdateCheckRun(ctx context.Context, req *JobStatusRequest, params UpdateCheckRunParams) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if err := gqc.initRepositoryClient(ctx); err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "unable to build client"))
	}

	// build update check run graphql mutation
	checkRunRequest, err := buildUpdateCheckRunGraphQL(req, params.CheckSuiteState, params.CheckRunID, params.WaitingOn)
	if err != nil {
		return tracing.RecordError(span, errs.Wrap(err, "Error generating check run request"))
	}

	// check for annotation count mismatch
	if checkRunRequest.Output != nil && len(req.GetAnnotations()) != len(checkRunRequest.Output.Annotations) {
		gqc.logger.Report(
			ctx,
			errs.New("incoming annotation count does not match check run annotation count"),
			kvp.Int("gh.launch.incoming_annotation.count", len(req.GetAnnotations())),
			kvp.Int("gh.launch.outgoing_annotation.count", len(checkRunRequest.Output.Annotations)),
			kvp.String("gh.check_run.global_id", params.CheckRunID.String()),
		)
	}

	gqc.labLogger.Debug(ctx, "debugging update check run request", kvp.Any("gh.launch.check_suite.request", checkRunRequest))

	// update dotcom via graphql mutation
	res, err := gqc.repoClient.UpdateCheckRun(ctx, *checkRunRequest)
	if err != nil {
		return tracing.RecordError(span, err)
	}
	if res.CheckRunIDPair.IsZeroValue() {
		return tracing.RecordError(span, errs.New("CheckRunIDPair not found in output"))
	}

	gqc.labLogger.Debug(ctx, "debugging update check run response", kvp.Any("gh.launch.check_run.response", res))

	return nil
}

func buildCreateCheckRunGraphQL(update *JobStatusRequest, checkSuiteState *types.CheckSuiteState, waitingOn *WaitingOn) (*github.CreateCheckRunRequest, error) {
	steps := getStepsGraphQL(update.Steps)

	checkRunRequest := github.CreateCheckRunRequest{
		RepositoryID:            checkSuiteState.RepositoryID,
		CheckSuiteID:            checkSuiteState.CheckSuiteIDPair.GlobalID,
		ExternalID:              update.ExternalId,
		HeadSHA:                 checkSuiteState.EventSHA,
		Name:                    update.JobId,
		DisplayName:             update.DisplayName,
		Number:                  update.Number,
		Steps:                   steps,
		JobKey:                  update.JobKey,
		ParentJobID:             update.ParentJobId,
		RunnerID:                update.RunnerId,
		RunnerName:              update.RunnerName,
		RunnerGroupID:           update.RunnerGroupId,
		RunnerGroupName:         update.RunnerGroupName,
		IsClonedFromPreviousRun: update.IsClonedFromPreviousRun,
	}

	if len(update.Labels) > 0 {
		checkRunRequest.Labels = update.Labels
	}

	if update.Environment != nil {
		checkRunRequest.EnvironmentName = update.Environment.Name
	}

	checkRunRequest.Concurrency = getConcurrencyGraphQL(update.Concurrency, waitingOn)

	switch status := update.Progress.(type) {
	case *JobStatusRequest_InProgress:
		if status.InProgress.StartedAt != nil {
			startedAt := status.InProgress.StartedAt.AsTime()
			checkRunRequest.StartedAt = &startedAt
		}
		checkRunRequest.Status = string(getStatusName(status.InProgress.Status))

		if status.InProgress.LogStream != nil {
			checkRunRequest.StreamingLog = &github.StreamingLog{
				URL: status.InProgress.LogStream.Url,
			}
		}

		if status.InProgress.Log != nil && status.InProgress.Log.Url != "" {
			checkRunRequest.CompletedLog = &github.CompletedLog{
				URL:   status.InProgress.Log.Url,
				Lines: status.InProgress.Log.Lines,
			}
		}

	case *JobStatusRequest_Complete:
		startedAt := status.Complete.StartedAt.AsTime()
		completedAt := status.Complete.CompletedAt.AsTime()
		checkRunRequest.StartedAt = &startedAt
		checkRunRequest.CompletedAt = &completedAt
		checkRunRequest.Status = string(statusCompleted)
		checkRunRequest.Conclusion = string(getResultName(status.Complete.Result))

		if status.Complete.Log != nil && status.Complete.Log.Url != "" {
			checkRunRequest.CompletedLog = &github.CompletedLog{
				URL:   status.Complete.Log.Url,
				Lines: status.Complete.Log.Lines,
			}
		}

		if status.Complete.SummaryUrl != "" {
			checkRunRequest.JobSummary = &github.JobSummary{
				URL: status.Complete.SummaryUrl,
			}
		}

		if len(update.Annotations) > 0 {
			annotations, err := getJobPostbackAnnotationsGraphQL(update)
			if err != nil {
				return nil, err
			}
			checkRunRequest.Output = &github.CheckRunOutput{
				Title:       update.GetDisplayName(),
				Summary:     getAnnotationSummary(update.Annotations),
				Annotations: annotations,
			}
		}
	}

	return &checkRunRequest, nil
}

func buildUpdateCheckRunGraphQL(update *JobStatusRequest, checkSuiteState *types.CheckSuiteState, checkRunID types.GlobalID, waitingOn *WaitingOn) (*github.UpdateCheckRunRequest, error) {
	steps := getStepsGraphQL(update.Steps)

	checkRunRequest := github.UpdateCheckRunRequest{
		CheckRunID:              checkRunID,
		RepositoryID:            checkSuiteState.RepositoryID,
		ExternalID:              update.ExternalId,
		Name:                    update.JobId,
		DisplayName:             update.DisplayName,
		Number:                  update.Number,
		Steps:                   steps,
		RunnerID:                update.RunnerId,
		RunnerName:              update.RunnerName,
		RunnerGroupID:           update.RunnerGroupId,
		RunnerGroupName:         update.RunnerGroupName,
		IsClonedFromPreviousRun: update.IsClonedFromPreviousRun,
	}

	if update.Environment != nil {
		checkRunRequest.EnvironmentName = update.Environment.Name
		checkRunRequest.EnvironmentURL = update.Environment.Url
	}

	if len(update.Labels) > 0 {
		checkRunRequest.Labels = update.Labels
	}

	checkRunRequest.Concurrency = getConcurrencyGraphQL(update.Concurrency, waitingOn)

	switch status := update.Progress.(type) {
	case *JobStatusRequest_InProgress:
		if status.InProgress.StartedAt != nil {
			startedAt := status.InProgress.StartedAt.AsTime()
			checkRunRequest.StartedAt = &startedAt
		}
		checkRunRequest.Status = string(getStatusName(status.InProgress.Status))

		if status.InProgress.LogStream != nil {
			checkRunRequest.StreamingLog = &github.StreamingLog{
				URL: status.InProgress.LogStream.Url,
			}
		}

		if status.InProgress.Log != nil && status.InProgress.Log.Url != "" {
			checkRunRequest.CompletedLog = &github.CompletedLog{
				URL:   status.InProgress.Log.Url,
				Lines: status.InProgress.Log.Lines,
			}
		}

	case *JobStatusRequest_Complete:
		startedAt := status.Complete.StartedAt.AsTime()
		completedAt := status.Complete.CompletedAt.AsTime()
		checkRunRequest.StartedAt = &startedAt
		checkRunRequest.CompletedAt = &completedAt
		checkRunRequest.Status = string(statusCompleted)
		checkRunRequest.Conclusion = string(getResultName(status.Complete.Result))

		if status.Complete.Log != nil && status.Complete.Log.Url != "" {
			checkRunRequest.CompletedLog = &github.CompletedLog{
				URL:   status.Complete.Log.Url,
				Lines: status.Complete.Log.Lines,
			}
		}

		if status.Complete.SummaryUrl != "" {
			checkRunRequest.JobSummary = &github.JobSummary{
				URL: status.Complete.SummaryUrl,
			}
		}

		if len(update.Annotations) > 0 {
			annotations, err := getJobPostbackAnnotationsGraphQL(update)
			if err != nil {
				return nil, err
			}
			checkRunRequest.Output = &github.CheckRunOutput{
				Title:       update.GetDisplayName(),
				Summary:     getAnnotationSummary(update.Annotations),
				Annotations: annotations,
			}
		}
	}

	return &checkRunRequest, nil
}

func getJobPostbackAnnotationsGraphQL(req *JobStatusRequest) ([]github.CheckRunAnnotation, error) {
	cras := make([]github.CheckRunAnnotation, 0, len(req.Annotations))
	for _, ann := range req.Annotations {

		name, err := getAnnotationLevelName(ann.AnnotationLevel)
		if err != nil {
			return cras, errs.Wrap(err, "unable to determine a valid annotation level name")
		}

		cra := github.CheckRunAnnotation{
			AnnotationLevel: name,
			Message:         ann.GetMessage(),
			RawDetails:      ann.GetRawDetails(),
			Path:            ann.GetPath(),
			Title:           ann.GetTitle(),
			Location:        getAnnotationRangeGraphQL(ann),
		}

		cras = append(cras, cra)
	}
	return cras, nil
}

func getStepsGraphQL(in []*JobStep) []github.CheckStepData {
	var out []github.CheckStepData
	for _, s := range in {
		newStep := github.CheckStepData{
			ExternalID: s.ExternalId,
			Name:       s.Name,
			Number:     s.Number,
		}

		switch st := s.Progress.(type) {
		case *JobStep_Queued:
			newStep.Status = string(statusQueued)
		case *JobStep_InProgress:
			startedAt := st.InProgress.StartedAt.AsTime()
			newStep.Status = string(getStatusName(st.InProgress.Status))
			newStep.StartedAt = &startedAt

		case *JobStep_Complete:
			startedAt := st.Complete.StartedAt.AsTime()
			completedAt := st.Complete.CompletedAt.AsTime()
			newStep.Status = string(statusCompleted)
			newStep.Conclusion = string(getResultName(st.Complete.Result))
			newStep.StartedAt = &startedAt
			newStep.CompletedAt = &completedAt
			if st.Complete.Log != nil {
				newStep.CompletedLog = &github.CompletedLog{
					URL:   st.Complete.Log.Url,
					Lines: st.Complete.Log.Lines,
				}
			}
		}

		out = append(out, newStep)
	}

	return out
}

func getAnnotationRangeGraphQL(ann *Annotation) github.CheckAnnotationRange {
	return github.CheckAnnotationRange{
		StartLine:   int(ann.GetStartLine()),
		EndLine:     int(ann.GetEndLine()),
		StartColumn: int(ann.GetStartColumn()),
		EndColumn:   int(ann.GetEndColumn()),
		StepNumber:  int(ann.GetStepNumber()),
	}
}

func getConcurrencyGraphQL(in *Concurrency, waitingOn *WaitingOn) *github.Concurrency {
	var out *github.Concurrency
	if in != nil {
		out = &github.Concurrency{
			Group: in.Group,
		}
		if in.WaitingOnResource != nil && waitingOn != nil {
			out.WaitingOnResource = &github.WaitingOnResource{
				CheckSuiteID: waitingOn.CheckSuiteID,
				CheckRunID:   waitingOn.CheckRunID,
				Identifier:   in.WaitingOnResource.Identifier,
			}
		}
	}

	return out
}

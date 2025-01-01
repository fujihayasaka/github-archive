package workflowinvoker

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/go-kvp"
	errs "github.com/pkg/errors"
	"github.com/shurcooL/githubv4"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"
	"github.com/github/launch/pkg/results/entities/checks"
	"github.com/github/launch/pkg/results/entities/events"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/results"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/slometrics"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/workflowbuild/build"
	"github.com/github/launch/workflowparser"

	terrors "github.com/github/launch/types/errors"
)

const annotationFailureLevel = string(githubv4.CheckAnnotationLevelFailure)
const annotationWarningLevel = string(githubv4.CheckAnnotationLevelWarning)

// Template for generic errors
const supportTemplate = `An unexpected error has occurred and we've been automatically notified. Errors are sometimes temporary, so please try again.

If the problem persists, please check whether the Actions service is operating normally at https://githubstatus.com. If not, please try again once the outage has been resolved.

%s`

// Users on GHES shouldn't check the status page
const enterpriseSupportTemplate = `An unexpected error has occurred. Errors are sometimes temporary, so please try again.

%s`

const contactSupportTemplate = `Should you need to contact Support, please visit https://support.github.com/contact and include request ID: %s`

type startErrorType string

const (
	certGeneratorErrType            startErrorType = "CertGenerator"
	planningErrType                 startErrorType = "FailedToPlan"
	filterFlowsErrType              startErrorType = "FailedToFilterPlans"
	newCheckSuiteStateErrType       startErrorType = "NewCheckSuiteState"
	updateCheckSuiteStateErrType    startErrorType = "UpdateCheckSuiteState"
	parserErrorErrType              startErrorType = "parser_error"
	calculatePermissionsErrType     startErrorType = "CalculatePermissions"
	createWorkflowRunResultsErrType startErrorType = "CreateWorkflowRunResultsError"
	// Parsing error returned by Actions Service
	azpParserErrorErrType           startErrorType = "azp_parser_error"
	reportingMetadataErrType        startErrorType = "ReportingMetadata"
	runErrType                      startErrorType = "Run"
	validateActionAllowedErrType    startErrorType = "validateActionAllowed"
	validateWorkflowsAllowedErrType startErrorType = "validateWorkflowsAllowed"
	// occurs if a workflowbuild backend cannot be initialized
	getBackendErrType               startErrorType = "getBackend"
	abuseContextErrType             startErrorType = "abuseContextErr"
	newWorkflowBuildErrType         startErrorType = "NewWorkflowBuild"
	buildPersistError               startErrorType = "BuildPersistError"
	reachabilityCheckErrType        startErrorType = "ReachabilityCheckError"
	unreachableErrType              startErrorType = "UnreachableError"
	resetWorkflowBuildErrType       startErrorType = "ResetWorkflowBuildError"
	publicForkPRErrType             startErrorType = "PublicForkPRError"
	dependabotRefCheckErrType       startErrorType = "DependabotRefCheckError"
	parseWorkflowPlanIDErrType      startErrorType = "ParseWorkflowPlanIdError"
	getOrchestrationContextsErrType startErrorType = "GetOrchestrationContextsError"
	customImageGenErrType           startErrorType = "CustomImageGenError"
	isActionRequiredErrType         startErrorType = "IsActionRequiredError"
)

// MultiWorkflowStartErr represents one or more WorkflowStartErrors.
// Implemented by WorkflowStartError and multiWorkflowStartErr
type MultiWorkflowStartErr interface {
	Error() string
	Errors() []*WorkflowStartErr
	IsRetryable() bool
	IsUserError() bool
}

// WorkflowStartErr encompasses all the information necessary to propagate errors encountered early on in Invoker.Start.
type WorkflowStartErr struct {
	workflowFilePath string
	data             *types.WorkflowInvocationData
	backend          types.WorkflowBackend
	// checkSuiteID is the id of an existing check suite if already created
	checkSuiteID           types.GlobalID
	errorType              startErrorType
	flowIdentifier         string
	stepErr                error
	rerunnable             bool
	workflowExecutionGraph string
	// after Persist is called we have a workflow_builds row
	workflowBuildID     *int64
	workflowExecutionID *types.WorkflowExecutionID
	retryable           bool

	// Populated only for required workflows
	workflowFileCheckoutSHA types.CommitSha
	workflowFileRef         string
}

type WorkflowStartErrorContext struct {
	workflowFilePath string
	data             *types.WorkflowInvocationData
	checkSuiteID     types.GlobalID
	flowIdentifier   string
	rerunnable       bool
	// after Persist is called we have a workflow_builds row
	workflowBuildID     *int64
	workflowExecutionID *types.WorkflowExecutionID

	// Populated only for required workflows
	workflowFileCheckoutSHA types.CommitSha
	workflowFileRef         string
}

type multiWorkflowStartErr struct {
	errs []*WorkflowStartErr
}

func NewWorkflowStartErrorContext(invocation Invocation, data *types.WorkflowInvocationData) *WorkflowStartErrorContext {
	return NewBuildStartErrContext("BuildFailed", "", invocation, data, "", "")
}

func NewBuildStartErrContext(path, identifier string, invocation Invocation, data *types.WorkflowInvocationData, workflowFileCheckoutSHA types.CommitSha, workflowFileRef string) *WorkflowStartErrorContext {
	startErr := &WorkflowStartErrorContext{
		data:                    data,
		flowIdentifier:          identifier,
		workflowFilePath:        path,
		rerunnable:              invocation.ExistingCheckSuite != nil && invocation.Event.Payload != nil,
		workflowFileCheckoutSHA: workflowFileCheckoutSHA,
		workflowFileRef:         workflowFileRef,
	}

	// reruns by definition have a build row, or we wouldn't have found one in the DB
	if invocation.ExistingCheckSuite != nil {
		startErr.checkSuiteID = invocation.ExistingCheckSuite.CheckSuiteIDPair.GlobalID

		startErr.workflowBuildID = &invocation.ExistingCheckSuite.WorkflowBuildDatabaseID
		startErr.flowIdentifier = invocation.ExistingCheckSuite.FlowIdentifier
		startErr.workflowFilePath = invocation.ExistingCheckSuite.WorkflowFilePath
	}
	return startErr
}

// NewWorkflowStartError returns a workflow error that is retryable.
func NewWorkflowStartError(errCtx *WorkflowStartErrorContext, err error, errorType startErrorType) *WorkflowStartErr {
	return newWorkflowStartError(errCtx, types.WorkflowBackendInconclusive, err, errorType, true)
}

func NewWorkflowStartErrorWithBackend(errCtx *WorkflowStartErrorContext, backend types.WorkflowBackend, err error, errorType startErrorType) *WorkflowStartErr {
	return newWorkflowStartError(errCtx, backend, err, errorType, true)
}

// NewPermanentWorkflowStartError returns a workflow error that is not
// retryable.
func NewPermanentWorkflowStartError(errCtx *WorkflowStartErrorContext, err error, errorType startErrorType) *WorkflowStartErr {
	return newWorkflowStartError(errCtx, types.WorkflowBackendInconclusive, err, errorType, false)
}

func NewPermanentWorkflowStartErrorWithBackend(errCtx *WorkflowStartErrorContext, backend types.WorkflowBackend, err error, errorType startErrorType) *WorkflowStartErr {
	return newWorkflowStartError(errCtx, backend, err, errorType, false)
}

func newWorkflowStartError(errCtx *WorkflowStartErrorContext, backend types.WorkflowBackend, err error, errorType startErrorType, retryable bool) *WorkflowStartErr {
	startErr := &WorkflowStartErr{
		workflowFilePath:        errCtx.workflowFilePath,
		data:                    errCtx.data,
		flowIdentifier:          errCtx.flowIdentifier,
		rerunnable:              errCtx.rerunnable,
		workflowBuildID:         errCtx.workflowBuildID,
		workflowExecutionID:     errCtx.workflowExecutionID,
		workflowFileCheckoutSHA: errCtx.workflowFileCheckoutSHA,
		workflowFileRef:         errCtx.workflowFileRef,

		errorType: errorType,
		stepErr:   err,
		retryable: retryable,
		backend:   backend,
	}

	if errCtx.checkSuiteID != types.NilGlobalID {
		startErr.checkSuiteID = errCtx.checkSuiteID
	}

	return startErr
}

func (w *WorkflowStartErr) Error() string {
	return w.stepErr.Error()
}

func (w *WorkflowStartErr) Errors() []*WorkflowStartErr {
	// multierror support: return a slice with just this error.
	return []*WorkflowStartErr{w}
}

// GetErrorType return the error type text
func (w *WorkflowStartErr) GetErrorType() string {
	return string(w.errorType)
}

// GetErrorStatus returns the error status text
// varying on whether the error is a UserError
func (w *WorkflowStartErr) GetErrorStatus() string {
	if w.IsUserError() {
		return "user_error"
	}

	return "error"
}

func (w *WorkflowStartErr) IsUserError() bool {
	return terrors.IsUserError(w.stepErr)
}

func (w *WorkflowStartErr) IsRetryable() bool {
	return w.retryable
}

func NewMultiWorkflowStartError(errs []*WorkflowStartErr) MultiWorkflowStartErr {
	if len(errs) < 1 {
		return nil
	}

	return &multiWorkflowStartErr{errs}
}

func (m *multiWorkflowStartErr) Errors() []*WorkflowStartErr {
	return m.errs
}

// IsRetryable Returns true if any of the errors are retryable.
func (m *multiWorkflowStartErr) IsRetryable() bool {
	for _, startErr := range m.errs {
		if startErr.retryable {
			return true
		}
	}

	return false
}

// IsUserError returns true if all the errors are user errors.
func (m *multiWorkflowStartErr) IsUserError() bool {
	if len(m.errs) < 1 {
		return false
	}

	for _, startErr := range m.errs {
		if !startErr.IsUserError() {
			return false
		}
	}
	return true
}

func (m *multiWorkflowStartErr) Error() string {
	// Return a simple error message if there's only one error.
	if len(m.errs) == 1 {
		return m.errs[0].Error()
	}

	for _, startErr := range m.errs {
		if startErr.retryable {
			return fmt.Sprintf("%d workflow start errors. First retryable error: %s", len(m.errs), startErr)
		}
	}

	return fmt.Sprintf("%d workflow start errors. First error: %s", len(m.errs), m.errs[0])
}

type WorkflowStartErrHandlerFactory interface {
	Build(*Observability, Invocation, github.Client, ghtwirp.Client, results.Client, bool, bool) WorkflowStartErrHandler
}

type workflowStartErrHandlerFactory struct {
	repo         deployer.WorkflowBuildsRepository
	sloReporter  *slometrics.Reporter
	isEnterprise bool
}

func NewErrorHandlerFactory(repo deployer.WorkflowBuildsRepository, sloReporter *slometrics.Reporter, isEnterprise bool) WorkflowStartErrHandlerFactory {
	return &workflowStartErrHandlerFactory{
		repo:         repo,
		sloReporter:  sloReporter,
		isEnterprise: isEnterprise,
	}
}

func (f *workflowStartErrHandlerFactory) Build(
	obs *Observability,
	invocation Invocation,
	client github.Client,
	twirpClient ghtwirp.Client,
	resultsClient results.Client,
	isEnterprise bool,
	skipParserErrors bool,
) WorkflowStartErrHandler {
	return NewErrorHandler(
		obs,
		invocation,
		f.repo,
		client,
		twirpClient,
		f.sloReporter,
		resultsClient,
		isEnterprise,
		skipParserErrors,
	)
}

type WorkflowStartErrHandler interface {
	handlePanic(context.Context, *types.WorkflowInvocationData)
	CreateErrorCheckSuite(context.Context, *WorkflowStartErr)
	notifyInvalidWorkflow(context.Context, string, error, *types.WorkflowInvocationData, *InvokingEvent, types.CommitSha)
}

type workflowStartErrHandler struct {
	obs              *Observability
	invocation       Invocation
	repo             deployer.WorkflowBuildsRepository
	client           github.Client
	twirpClient      ghtwirp.Client
	sloReporter      *slometrics.Reporter
	resultsClient    results.Client
	isEnterprise     bool
	skipParserErrors bool
}

func NewErrorHandler(
	obs *Observability,
	invocation Invocation,
	repo deployer.WorkflowBuildsRepository,
	client github.Client,
	twirpClient ghtwirp.Client,
	sloReporter *slometrics.Reporter,
	resultsClient results.Client,
	isEnterprise bool,
	skipParserErrors bool,
) WorkflowStartErrHandler {
	return &workflowStartErrHandler{
		obs:              obs,
		sloReporter:      sloReporter,
		invocation:       invocation,
		repo:             repo,
		client:           client,
		twirpClient:      twirpClient,
		isEnterprise:     isEnterprise,
		resultsClient:    resultsClient,
		skipParserErrors: skipParserErrors,
	}
}

// CreateErrorCheckSuite logs, stats, and notifies the updaters of
// the error generated within the Invoker.Start method.
//
// Warning: this method can be called multiple times for the
// same invocation. It's called from two different places:
//  1. main invoker body which will cause invocation to cease
//  2. the job in `startWorkflow`.
//     a. this will not cause invocation to cease, and if multiple jobs fail here
//     this will be called multiple times
//     b. this means the method can be called concurrently
func (h *workflowStartErrHandler) CreateErrorCheckSuite(ctx context.Context, w *WorkflowStartErr) {
	// set stat tags on the request metadata
	// N.B: this is used in metrics sent by the invoker after
	// this call
	// TODO - see the note above. There is a last write win here for status/error_type
	rmd := mw.GetRequestMetadata(ctx)
	rmd.TagStatsWith(reqmeta.Tags{
		"status":     w.GetErrorStatus(),
		"error_type": w.GetErrorType(),
		"backend":    w.backend.String(),
	})

	// The parent context may be cancelled.
	ctx = appcontext.Fork(ctx)

	var workflowExecutionID types.WorkflowExecutionID
	if w.workflowExecutionID != nil {
		workflowExecutionID = *w.workflowExecutionID
	} else {
		workflowExecutionID = types.NewRandomWorkflowExecutionID()
	}

	var checkSuiteID types.GlobalID
	if w.checkSuiteID != types.NilGlobalID {
		checkSuiteID = w.checkSuiteID
	} else if h.invocation.PrecreatedCheckSuiteID != nil {
		checkSuiteID = *h.invocation.PrecreatedCheckSuiteID
	}

	if w.IsUserError() {
		h.obs.Log(ctx, "workflow invocation skipped because of user error",
			kvp.Err(w.stepErr),
			kvp.String("exception.type", w.GetErrorType()),
			kvp.String("gh.launch.error_status", w.GetErrorStatus()),
			kvp.String("gh.launch.flow_identifier", w.flowIdentifier),
		)
	} else if w.errorType == parserErrorErrType && h.skipParserErrors {
		h.obs.Debug(ctx, "queue run failure ignore due to expected parser error",
			kvp.Err(w.stepErr),
			kvp.String("exception.type", w.GetErrorType()),
			kvp.String("gh.launch.error_status", w.GetErrorStatus()),
			kvp.String("gh.launch.flow_identifier", w.flowIdentifier),
		)
	} else if w.stepErr != nil {
		h.obs.Report(ctx, w.stepErr)
		msg := slometrics.NewQueueRunMessage(
			ctx, &h.obs.Observability,
			slometrics.ActorID(h.invocation.TriggeringActor.ID), slometrics.OwnerID(w.data.Owner.GlobalID), slometrics.RepositoryID(h.invocation.Target.RepositoryID), h.invocation.Event.Name, h.invocation.Event.Action,
			slometrics.WithWorkflowExecutionID(workflowExecutionID),
			slometrics.WithRerunInfo(h.invocation.RerunInfo))
		h.sloReporter.ReportQueueRunError(ctx, &h.obs.Observability, msg, w.GetErrorType())
	}

	errID := mw.GetGitHubRequestID(ctx)
	updateWorkflowBuildWithCheckSuiteID := true

	// If we haven't persisted the workflow build yet, do so now
	if w.workflowBuildID == nil {
		if checkSuiteID != types.NilGlobalID {
			// Check suite has already been persisted, we don't need to update the workflow build later
			updateWorkflowBuildWithCheckSuiteID = false
		}

		workflowBuildID, err := h.repo.PersistError(
			ctx,
			h.invocation.Target.RepositoryID,
			workflowExecutionID,
			h.invocation.Event.Name,
			w.data.References.EventCommit.CommitSHA,
			w.data.References.EventCommit.GitRef,
			errID,
			checkSuiteID,
			w.workflowFilePath,
			h.invocation.ExecutingActor.ID,
			h.invocation.TriggeringActor.ID,
		)
		if err != nil {
			h.obs.Report(ctx, errs.Wrap(err, "failed to create build row on error"))
			return
		}

		w.workflowBuildID = &workflowBuildID
	}

	_, headRepositoryID := extractPRData(ctx, build.RunEnvironment{}, &h.invocation.Event, &h.invocation.Target)

	// Re-use check suite if it's been created, otherwise, create it on demand
	if checkSuiteID == types.NilGlobalID {
		checkSuiteState, err := createCheckSuite(
			ctx,
			h.client,
			workflowExecutionID,
			h.invocation,
			w.data.References.EventCommit,
			w.data.References.CheckoutCommit,
			headRepositoryID,
			w.flowIdentifier,
			w.workflowFilePath,
			types.NilGlobalID,
			w.rerunnable,
			w.workflowExecutionGraph,
			&[]github.CheckSuiteAnnotation{
				errorToCheckSuiteAnnotation(
					w.workflowFilePath,
					errID,
					w.stepErr,
					// If the error is not a user error, obfuscate the error message
					!terrors.IsUserError(w.stepErr),
					h.isEnterprise,
				),
			},
			github.CheckSuiteStartupFailureConclusion,
			"", // ReferencedWorkflows aren't needed since this method is only called to retieve a checkSuiteId.
			w.workflowFileCheckoutSHA,
			types.CommitShaZeroValue,        // A failed workflow run will not be eligible for reuse so no treeId information needs to be saved.
			types.GitRef(w.workflowFileRef), // the workflowFileRef provided by the previous invocation, used for ruleset workflows only
		)

		if err != nil {
			rmd.TagStatsWith(reqmeta.Tags{"status": "error", "error_type": "NewCheckSuiteState"})
			h.obs.Report(ctx, errs.New("failed to create check suite to report error"), kvp.Err(err))
			return
		}

		checkSuiteID = checkSuiteState.CheckSuiteIDPair.GlobalID
		w.checkSuiteID = checkSuiteID
	} else {
		h.updateCheckSuiteWithError(ctx, checkSuiteID, workflowExecutionID, w.workflowFilePath, errID, w.stepErr)
	}

	if updateWorkflowBuildWithCheckSuiteID {
		// Now that we have a check suite, update work flow build with check suite id and transition
		// to error state
		err := h.repo.TransitionToError(
			ctx,
			*w.workflowBuildID,
			checkSuiteID,
		)
		if err != nil {
			h.obs.Report(ctx, errs.Wrap(err, "failed to update build row on error"))
			return
		}
	}
}

func (h *workflowStartErrHandler) handlePanic(ctx context.Context, data *types.WorkflowInvocationData) {
	if r := recover(); r != nil {
		startErr := &WorkflowStartErr{
			data:           data,
			errorType:      "panic",
			flowIdentifier: "",
			stepErr:        nil,
			// we're creating an error check suite below.
			retryable: false,
		}

		if err, ok := r.(error); ok {
			startErr.stepErr = errs.Wrap(err, "error: panic recovered")
		} else {
			startErr.stepErr = errs.Errorf("%v", r)
		}

		h.CreateErrorCheckSuite(ctx, startErr)
	}
}

type errorWithPosition interface {
	Position() (int, int)
}

func errorToCheckSuiteAnnotation(workflowPath string, errID string, err error, obfuscate, isEnterprise bool) github.CheckSuiteAnnotation {
	switch customErr := err.(type) {
	case errorWithPosition: // eg azperrors.AZPSyntaxError, wfparser.WorkflowParseError, expressions.ExpressionEngineError
		{
			line, col := customErr.Position()
			return createWorkflowErrorAnnotation(workflowPath, err, line, col)
		}
	case workflowparser.ParseError:
		{
			return createWorkflowErrorAnnotation(workflowPath, customErr, customErr.Line(), 0)
		}
	default:
		{
			return createGenericErrorAnnotation(errID, err, obfuscate, isEnterprise)
		}
	}
}

// For annotations that are not attached to a specific source location, use this default range
var defaultAnnotationRange = github.CheckAnnotationRange{
	StartLine: 1,
	EndLine:   1,
}

func createWorkflowErrorAnnotation(filename string, err error, line, col int) github.CheckSuiteAnnotation {
	var location github.CheckAnnotationRange
	if line <= 0 {
		// For invalid locations, we show the annotation at the beginning of the file
		location = defaultAnnotationRange
	} else {
		location = github.CheckAnnotationRange{
			StartLine:   line,
			EndLine:     line,
			StartColumn: col,
			EndColumn:   col,
		}
	}

	annotation := github.CheckSuiteAnnotation{
		Title:           "Invalid workflow file",
		Path:            filename,
		Message:         err.Error(),
		AnnotationLevel: annotationFailureLevel,
		Location:        location,
	}

	return annotation
}

func createGenericErrorAnnotation(errID string, err error, obfuscate, isEnterprise bool) github.CheckSuiteAnnotation {
	var message string

	// We only want to return the real error message for certain errors, for others we are using a generic
	// template.
	if obfuscate {
		contactSupportMessage := fmt.Sprintf(contactSupportTemplate, errID)

		if isEnterprise {
			message = fmt.Sprintf(enterpriseSupportTemplate, contactSupportMessage)
		} else {
			message = fmt.Sprintf(supportTemplate, contactSupportMessage)
		}
	} else {
		message = err.Error()
	}

	return github.CheckSuiteAnnotation{
		Title: "Error",
		// We do not want to use the real workflow path here. Most likely the error is not specific to the workflow file
		// and this pushes the error into the general annotations section.
		Path:            ".github",
		AnnotationLevel: annotationFailureLevel,
		Message:         message,
		// Set default range so that the annotation shows up
		Location: defaultAnnotationRange,
	}
}

// notifyInvalidWorkflow is called when an invalid workflow is detected during push event or an invoking event
func (h *workflowStartErrHandler) notifyInvalidWorkflow(ctx context.Context, workflowPath string, parseError error, data *types.WorkflowInvocationData, event *InvokingEvent, workflowFileCheckoutSHA types.CommitSha) {
	resolvedSHA := data.References.EventCommit.CommitSHA
	fields := []kvp.Field{
		kvp.String("gh.launch.workflow.file_path", workflowPath),
	}

	wfExecID := types.NewRandomWorkflowExecutionID()

	if h.skipParserErrors {
		h.obs.Debug(ctx, "queue run failure ignore due to expected parser error",
			kvp.Err(parseError),
			kvp.String("exception.type", string(parserErrorErrType)),
			kvp.String("gh.launch.error_status", "error"),
			kvp.String("gh.launch.workflow.file_path", workflowPath),
		)
	} else if terrors.IsInternalError(parseError) {
		h.obs.Report(ctx, parseError)
		msg := slometrics.NewQueueRunMessage(
			ctx,
			&h.obs.Observability,
			slometrics.ActorID(h.invocation.TriggeringActor.ID),
			slometrics.OwnerID(data.Owner.GlobalID),
			slometrics.RepositoryID(h.invocation.Target.RepositoryID),
			h.invocation.Event.Name,
			h.invocation.Event.Action,
			slometrics.WithWorkflowExecutionID(wfExecID),
			slometrics.WithRerunInfo(h.invocation.RerunInfo))
		h.sloReporter.ReportQueueRunError(ctx, &h.obs.Observability, msg, string(parserErrorErrType))
	} else {
		h.obs.Counter(ctx, metrickeys.UserSyntaxError, map[string]string{
			metrickeys.At: metrickeys.AtActionsParseTime,
		}, 1)
	}

	var csr *github.CreateCheckSuiteResponse
	var err error

	csr, err = h.createFailedSuiteWithSuiteLevelAnnotations(ctx, wfExecID, workflowPath, parseError, resolvedSHA, event, workflowFileCheckoutSHA)
	if err != nil {
		h.obs.Report(ctx, err, fields...)
		return
	}

	if csr != nil {
		fields = append(fields,
			kvp.String("gh.launch.workflow.execution.id", wfExecID.String()),
			kvp.String("gh.check_suite.global_id", csr.CheckSuiteIDPair.GlobalID.String()),
		)
	}

	h.obs.Log(ctx, "created error check suite for invalid workflow file", fields...)

	rID := mw.GetGitHubRequestID(ctx)
	_, err = h.repo.PersistError(
		ctx,
		h.invocation.Target.RepositoryID,
		wfExecID,
		h.invocation.Event.Name,
		data.References.EventCommit.CommitSHA,
		data.References.EventCommit.GitRef,
		rID,
		csr.CheckSuiteIDPair.GlobalID,
		workflowPath,
		h.invocation.ExecutingActor.ID,
		h.invocation.TriggeringActor.ID,
	)
	if err != nil {
		h.obs.Report(ctx, errs.Wrap(err, "failed to store a workflow_builds row for syntax error"), fields...)
		return
	}
}

func (h *workflowStartErrHandler) createFailedSuiteWithSuiteLevelAnnotations(ctx context.Context, wfExecID types.WorkflowExecutionID, workflowPath string, parseError error, resolvedSHA types.CommitSha, event *InvokingEvent, workflowFileCheckoutSHA types.CommitSha) (*github.CreateCheckSuiteResponse, error) {
	errID := mw.GetGitHubRequestID(ctx)
	annotations := []github.CheckSuiteAnnotation{
		errorToCheckSuiteAnnotation(
			workflowPath,
			errID,
			parseError,
			terrors.IsInternalError(parseError), // this is only called for invalid workflows, show all errors unless explicit internal error
			h.isEnterprise,
		),
	}

	_, headRepositoryID := extractPRData(ctx, build.RunEnvironment{}, &h.invocation.Event, &h.invocation.Target)

	h.obs.Debug(ctx, "annotation count on invalid workflow",
		kvp.Int("gh.launch.annotation_count", len(annotations)),
		kvp.String("gh.launch.annotation_level", "check_suite"),
		kvp.String("gh.launch.workflow.file_path", workflowPath),
	)
	ccsr := github.CreateCheckSuiteRequest{
		WorkflowExecutionID:     wfExecID,
		RepositoryID:            h.invocation.Target.RepositoryID,
		HeadSHA:                 resolvedSHA,
		HeadRepositoryID:        headRepositoryID,
		Rerequestable:           false,
		Name:                    workflowPath,
		EventName:               h.invocation.Event.Name,
		WorkflowFilePath:        workflowPath,
		CreatorID:               h.invocation.TriggeringActor.ID,
		ExplicitCompletion:      true,
		Annotations:             annotations,
		Conclusion:              github.CheckSuiteFailureConclusion.String(),
		TriggerID:               extractTrigger(ctx, h.twirpClient, event),
		WorkflowFileCheckoutSHA: workflowFileCheckoutSHA,
	}
	suiteResult, err := h.client.CreateCheckSuite(ctx, ccsr)
	if err != nil {
		return nil, errs.Wrap(err, "failed to create a check suite to notify user of invalid workflow")
	}

	return suiteResult, nil
}

func (h *workflowStartErrHandler) updateCheckSuiteWithError(ctx context.Context, checkSuiteID types.GlobalID, executionID types.WorkflowExecutionID, workflowPath string, errID string, err error) {
	annotation := errorToCheckSuiteAnnotation(
		workflowPath,
		errID,
		err,
		// If the error is not a user error, obfuscate the error message
		!terrors.IsUserError(err),
		h.isEnterprise,
	)

	if launchconfig.UsingResultsService() {
		_, repoID, err := h.invocation.Target.RepositoryID.Decode()
		if err != nil {
			h.obs.Report(ctx, errs.Wrap(err, "invalid repository global id"))
			return
		}

		_, checkSuiteID, err := checkSuiteID.Decode()
		if err != nil {
			h.obs.Report(ctx, errs.Wrap(err, "invalid check suite global id"))
			return
		}

		err = h.resultsClient.UpdateWorkflowRun(ctx, &events.WorkflowRunUpdate{
			RepositoryId:    repoID,
			WorkflowRunGuid: executionID.String(),
			CheckSuiteId:    checkSuiteID,
			Status:          checks.CheckStatus_STATUS_COMPLETED,
			Conclusion:      checks.CheckConclusion_CONCLUSION_STARTUP_FAILURE,
			CompletedAt:     timestamppb.Now(),
			Annotations:     []*checks.CheckAnnotation{graphQLToProtoAnnotation(annotation)},
		})
		if err != nil {
			h.obs.Report(ctx, errs.Wrap(err, "Could not update check suite within updateCheckSuiteWithError via results"))
			return
		}
	} else {
		// We need to mark the check suite as completed
		checkSuiteRes, err := h.client.UpdateCheckSuite(ctx, github.UpdateCheckSuiteRequest{
			RepositoryID: h.invocation.Target.RepositoryID,
			CheckSuiteID: checkSuiteID,
			Conclusion:   github.CheckSuiteStartupFailureConclusion.String(),
			Annotations:  []github.CheckSuiteAnnotation{annotation},
		})
		if err != nil {
			h.obs.Report(ctx, errs.Wrap(err, "Could not update check suite within updateCheckSuiteWithError"))
			return
		}
		if checkSuiteRes == nil {
			h.obs.Report(ctx, errors.New("Did not get response for updating check suite within updateCheckSuiteWithError"))
			return
		}
	}

	h.obs.Log(ctx, "Updated error check suite completed", kvp.String("gh.check_suite.global_id", checkSuiteID.String()))
}

func graphQLToProtoAnnotation(annotation github.CheckSuiteAnnotation) *checks.CheckAnnotation {
	level := checks.CheckAnnotation_LEVEL_FAILURE
	switch annotation.AnnotationLevel {
	case string(githubv4.CheckAnnotationLevelFailure):
		level = checks.CheckAnnotation_LEVEL_FAILURE
	case string(githubv4.CheckAnnotationLevelWarning):
		level = checks.CheckAnnotation_LEVEL_WARNING
	case string(githubv4.CheckAnnotationLevelNotice):
		level = checks.CheckAnnotation_LEVEL_NOTICE
	}

	return &checks.CheckAnnotation{
		AnnotationLevel: level,
		Message:         annotation.Message,
		Path:            wrapperspb.String(annotation.Path),
		Title:           wrapperspb.String(annotation.Title),
		StartLine:       wrapperspb.Int64(int64(annotation.Location.StartLine)),
		EndLine:         wrapperspb.Int64(int64(annotation.Location.EndLine)),
		StartColumn:     wrapperspb.Int64(int64(annotation.Location.StartColumn)),
		EndColumn:       wrapperspb.Int64(int64(annotation.Location.EndColumn)),
	}
}

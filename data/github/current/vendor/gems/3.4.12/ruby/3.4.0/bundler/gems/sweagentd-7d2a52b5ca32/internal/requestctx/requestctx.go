package requestctx

import (
	"context"
	"fmt"
	"hash/fnv"
	"net/http"
	"time"

	copilotUsersTwirp "github.com/github/copilot-twirp/proto/users/v1"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/ghchi"
	"github.com/github/sweagentd/internal/github/tokens"
)

type ctxKey string

var reqCtxKey ctxKey = "requestctx"

// GitHubTenantHeader is a request header containing tenant information
// for incoming requests the value will be the tenant slug. When used in
// outgoing calls the value of the header can either have a value of
// id=:tenantID or sc=:tenantShortCode or just slug value.
// Launch uses this header in API calls to the monolith (and other services) when NWOs are used instead of unique ids.
const GitHubTenantHeader = "X-GitHub-Tenant"

// GitHubTenantIDHeader is a request header containing the tenant id. This header
// is sent by clients and in webhook payloads
const GitHubTenantIDHeader = "X-GitHub-Tenant-ID"

// CtxData represents the data we store in a request context.
// An instance of this struct is injected into the request context by the
// MustComeFirstMiddleware. Fields in this struct are populated throughout the
// request and are available to middlewares and handlers, even outer middlewares
// that have a processing step after the request has been handled (i.e. logging
// and telemetry).
type CtxData struct {
	// TenantID is the tenant ID associated with the request.
	TenantID string
	// TenantSlug is the tenant slug associated with the request.
	TenantSlug string
	UserInfo   *UserInfo
	// RequestIP is the IP from which the request originated.
	RequestIP string
	// EventId is the event id of the event that triggered the request.
	EventId *string
	// HydroMessage is the message from the Hydro event that triggered a job.
	HydroMessage *HydroEvent
	// AqueductJob is the job that is being processed in the request.
	AqueductJob *CtxAqueductJob
	// Repo is the repository associated with the Hydro event.
	Repo *CtxRepo
	// Issue is the issue associated with the event and job.
	Issue *CtxIssue
	// PullRequest is the pull request associated with the event and job.
	PullRequest *CtxPullRequest
	// WorkflowRun is the workflow run associated with the event and job.
	WorkflowRun *CtxWorkflowRun
	// Job is the job in scope for this event or request.
	Job *CtxJob
	// Session is the session associated with the job.
	Session *CtxSession
	// JobUpdate is the specific callback event from a running job.
	JobUpdate *CtxJobUpdate
	// CodeScanningAlerts is the code scanning alerts in scope for this event or request.
	CodeScanningAlerts *CtxCodeScanningAlerts
	// ProblemStatement is the problem statement associated with the event.
	ProblemStatement *CtxProblemStatement
	// CopilotUserDetailsCache is a map of user ID to memoized Copilot user details to avoid refetching multiple times.
	CopilotUserDetailsCache map[int64]*copilotUsersTwirp.CopilotUserDetails
}

// AddData adds the given request data to the context.
func AddData(ctx context.Context, data *CtxData) context.Context {
	return context.WithValue(tokens.NewContext(ctx), reqCtxKey, data)
}

// NewContext creates a new context with an empty CtxData struct.
func NewContext(ctx context.Context) context.Context {
	// Create a new context with an empty CtxData struct.
	// This is used to ensure that the context always has a CtxData value,
	// even if no data is added later.
	return context.WithValue(tokens.NewContext(ctx), reqCtxKey, &CtxData{})
}

// Data returns the request data from the context. It will panic if there is
// no data in the context (which should never happen in production).
func Data(ctx context.Context) *CtxData {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok || d == nil {
		// This should never happen in production, so making it a panic saves us a lot of unnecessary error handling.
		panic(fmt.Errorf("context does not contain request context data"))
	}
	return d
}

// UserInfo describes the current authenticated user.
type UserInfo struct {
	// ID is the numeric ID of the user.
	ID uint64
	// Login is the user login.
	Login string
	// TrackingID is an opaque ID supplied by IDE tokens, that is passed to OpenAI for rate limiting
	// and abuse detection. Each GitHub user has a different ID.
	TrackingID string
	// RequestIP is the IP address from which the user request originated (rather than just the IP used to connect to the service).
	RequestIP string
	// TokenInfo describes the authenticated user. Value is empty if another
	// authentication method was used.
	TokenInfo *TokenInfo
}

// GetActorID returns the actor ID for the user.
// Implements the sweagentd.Actor interface.
func (user *UserInfo) GetActorID() int64 {
	return int64(user.ID)
}

// TokenInfo holds the result of authenticating a credential (e.g. PATv1, Fine-Grained PAT).
type TokenInfo struct {
	// SessionID is the id of the session, or 0 if the token is not tied to a session.
	SessionID int64
	// ApplicationID is the ID of the application that issued the token, or 0 if the token is not tied to an application.
	// Comes from `authnd`'s `application.id` attribute.
	// Defined here: https://github.com/github/authnd/blob/e940c8c70eb104d0df78c0bae92e972e29210742/internal/api/models/attributes.go#L26
	ApplicationID uint64
	// ApplicationType is the type of application that minted the token.
	// Comes from `authnd`'s `application.type` attribute.
	// Defined here: https://github.com/github/authnd/blob/b24e187fde8ecadfeb5f665051ce19e7f6441ca5/client/constants.go#L13-L15
	ApplicationType string
	// Type is the type of credential used to authenticate the token.
	// Comes from `authnd`'s `credential.type` attribute.
	// Defined here: https://github.com/github/authnd/blob/b24e187fde8ecadfeb5f665051ce19e7f6441ca5/client/constants.go#L17-L21
	Type string
	// Token is the token that was used to authenticate the user.
	Token string
	// OrganizationSSOAuthorizedIDs are the IDs of the organizations that were authorized by the user when the token was created.
	// Applies to Oauth tokens only.
	OrganizationSSOAuthorizedIDs []int64
}

// HydroEvent is the name of the Hydro event that triggered the job.
type HydroEvent struct {
	Topic      string
	Offset     int64
	Partition  int32
	EnvelopeId string
}

type CtxAqueductJob struct {
	Queue        string
	ID           string
	RequeueCount int32
}

type CtxRepo struct {
	ID      int64
	OwnerID int64
}

type CtxPullRequest struct {
	ID        *int64
	Number    int
	ReviewID  *int64
	CommentID *int64
	State     string
}

type CtxIssue struct {
	ID     int64
	Number int
}

type CtxWorkflowRun struct {
	ID    int64
	JobID *int64
}

type CtxJob struct {
	ID                string
	RepoID            int64
	OwnerID           int64
	ComputeID         string
	SessionID         string
	EventType         string
	AssignmentID      string
	ActorID           int64
	PullRequestID     int64
	PullRequestNumber int
	CreatedAt         int64
	CompletedAt       int64
	QueuedAt          int64
	Status            string
	BranchName        string
	Experiments       CtxExperiments
	CustomAgent       CtxCustomAgent
}

type CtxExperiments struct {
	Variations        map[string]any
	AssignmentContext string
}

type CtxCustomAgent struct {
	Name    string
	RepoID  int64
	OwnerID int64
	Version string
}

type CtxSession struct {
	ID            string
	State         string
	ResourceType  string
	ResourceID    int64
	EventType     string
	WorkflowRunID uint64
}

type CtxJobUpdate struct {
	Kind      string
	Action    string
	CreatedAt int64
}

type CtxCodeScanningAlerts struct {
	RepoID       int64
	OwnerID      int64
	ActorID      int64
	Assignees    []string
	AlertNumbers []int64
}

type CtxProblemStatement struct {
	Length       int
	Base64Length int
	// Source is the source of the problem statement,
	// for example "api", "issue" or "pull_request".
	Source string
	// TruncatedComments indicates whether the body of each comment was truncated.
	// Only applicable for issue and pull request generated problem statements.
	TruncatedComments bool
	// TruncatedDescription indicates whether the issue/pr description was truncated.
	// Only applicable for issue and pull request generated problem statements.
	TruncatedDescription bool
	// RemovedComments indicates whether comments were removed to reduce the size
	// of the generated problem statement.
	// Only applicable for issue and pull request generated problem statements.
	RemovedComments bool
	// RemovedCommentsCount is the number of comments that were removed.
	// This is only set if RemovedComments is true.
	// Only applicable for issue and pull request generated problem statements.
	RemovedCommentsCount int
}

// AddUser sets the given user info for the request. The request needs to have
// gone through MustComeFirstMiddleware beforehand.
func AddUser(ctx context.Context, userInfo *UserInfo) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.UserInfo = userInfo
	return nil
}

// User returns the user info set in the context.
func User(ctx context.Context) (*UserInfo, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.UserInfo, d.UserInfo != nil
}

// AddTenantID sets the given tenant ID in the context.
func AddTenantID(ctx context.Context, tenantID string) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.TenantID = tenantID
	return nil
}

// TenantID returns the tenant ID set in the context or falls back to the tenant package's GetTenantID function.
func TenantID(ctx context.Context) string {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if ok && d.TenantID != "" {
		return d.TenantID
	}

	return tenant.GetTenantID(ctx)
}

// AddTenantSlug sets the given tenant slug in the context.
func AddTenantSlug(ctx context.Context, slug string) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.TenantSlug = slug
	return nil
}

// TenantSlug returns the tenant slug set in the context or falls back to the tenant package's GetTenant function.
func TenantSlug(ctx context.Context) string {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if ok && d.TenantSlug != "" {
		return d.TenantSlug
	}

	return tenant.GetTenant(ctx)
}

// AddHydroMessage sets the given HydroEvent in the context.
func AddHydroMessage(ctx context.Context, msg HydroEvent) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.HydroMessage = &msg
	return nil
}

// HydroMessage returns the HydroMessage set in the context.
func HydroMessage(ctx context.Context) (*HydroEvent, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.HydroMessage, d.HydroMessage != nil
}

func AddAqueductJob(ctx context.Context, job *CtxAqueductJob) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.AqueductJob = job
	return nil
}

// AqueductJob returns the AqueductJob set in the context.
func AqueductJob(ctx context.Context) (*CtxAqueductJob, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.AqueductJob, d.AqueductJob != nil
}

// AddRepo sets the given HydroEventRepo in the context.
func AddRepo(ctx context.Context, repo CtxRepo) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.Repo = &repo
	return nil
}

// Repo returns the Repo set in the context.
func Repo(ctx context.Context) (*CtxRepo, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.Repo, d.Repo != nil
}

// AddIssue sets the given CtxIssue in the context.
func AddIssue(ctx context.Context, issue CtxIssue) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.Issue = &issue
	return nil
}

// Issue returns the CtxIssue set in the context.
func Issue(ctx context.Context) (*CtxIssue, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.Issue, d.Issue != nil
}

// AddPullRequest sets the given CtxPullRequest in the context.
func AddPullRequest(ctx context.Context, pr CtxPullRequest) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.PullRequest = &pr
	return nil
}

// PullRequest returns the CtxPullRequest set in the context.
func PullRequest(ctx context.Context) (*CtxPullRequest, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.PullRequest, d.PullRequest != nil
}

// AddWorkflowRun sets the given CtxWorkflowRun in the context.
func AddWorkflowRun(ctx context.Context, run *CtxWorkflowRun) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.WorkflowRun = run
	return nil
}

// WorkflowRun returns the CtxWorkflowRun set in the context.
func WorkflowRun(ctx context.Context) (*CtxWorkflowRun, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.WorkflowRun, d.WorkflowRun != nil
}

func AddJob(ctx context.Context, job *CtxJob) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.Job = job
	return nil
}

func Job(ctx context.Context) (*CtxJob, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.Job, d.Job != nil
}

func AddSession(ctx context.Context, session *CtxSession) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.Session = session
	return nil
}

func Session(ctx context.Context) (*CtxSession, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.Session, d.Session != nil
}

func AddJobUpdate(ctx context.Context, update *CtxJobUpdate) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.JobUpdate = update
	return nil
}

func JobUpdate(ctx context.Context) (*CtxJobUpdate, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.JobUpdate, d.JobUpdate != nil
}

func AddCodeScanningAlerts(ctx context.Context, alerts *CtxCodeScanningAlerts) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.CodeScanningAlerts = alerts
	return nil
}

func CodeScanningAlerts(ctx context.Context) (*CtxCodeScanningAlerts, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.CodeScanningAlerts, d.CodeScanningAlerts != nil
}

func AddProblemStatement(ctx context.Context, ps *CtxProblemStatement) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	d.ProblemStatement = ps
	return nil
}

func ProblemStatement(ctx context.Context) (*CtxProblemStatement, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	return d.ProblemStatement, d.ProblemStatement != nil
}

// ToTelemetry returns the request context data as a list of key-value pairs
// that can be attached to telemetry events to provide context about the request.
func ToTelemetry(ctx context.Context, r *http.Request) (stats stats.Tags, exception map[string]string, log []kvp.Field) {
	return statsTags(ctx, r), exceptionTags(ctx, r), logFields(ctx, r)
}

// statsTags returns a map of key-value pairs that can be
// attached to stats events to provide context about the request.
// Care not to add too many tags here, as they are indexed by Datadog.
// The HTTP request `r` is optional and can be `nil` - if present,
// fields from the request like method will be included.
func statsTags(ctx context.Context, r *http.Request) stats.Tags {
	tags := stats.Tags{}

	hydroMsg, ok := HydroMessage(ctx)
	if ok {
		tags["topic"] = hydroMsg.Topic
		tags["partition"] = fmt.Sprintf("%d", hydroMsg.Partition)
	}

	aqueductJob, ok := AqueductJob(ctx)
	if ok {
		tags["aqueduct.queue"] = aqueductJob.Queue
	}

	// Normally, you wouldn't see data like user, repo, issue in the stats tags.
	// We are adding this data via hashing as a starting place to try identifying single user failure modes.
	user, hasUser := User(ctx)
	if hasUser {
		tags["user_bucket"] = fmt.Sprintf("%d", bucketUInt64(user.ID))
	}

	repo, ok := Repo(ctx)
	if ok {
		tags["repo_bucket"] = fmt.Sprintf("%d", bucketInt64(repo.ID))
	}

	issue, ok := Issue(ctx)
	if ok {
		tags["issue_bucket"] = fmt.Sprintf("%d", bucketInt64(issue.ID))
	}

	pr, ok := PullRequest(ctx)
	if ok {
		if pr.ID != nil {
			tags["pr_bucket"] = fmt.Sprintf("%d", bucketInt64(*pr.ID))
		}
	}

	if r != nil {
		tags["http.request.method"] = r.Method
		// We don't want to tag path here because it will create way too high of cardinality for the tag.
		tags["url.route"] = ghchi.Route(r)
	}

	return tags
}

// numberOfStatsBucketsToCoarsenTo is the number of buckets we "coarsen" (that is, to reduce cardinality of) input data to.
// It might turn out over time that we want different levels of cardinality for different tags, but for now this is fine.
var numberOfStatsBucketsToCoarsenTo uint64 = 100

func bucketUInt64(toHash uint64) uint64 {
	h := fnv.New64a()
	h.Write([]byte(fmt.Sprintf("%d", toHash)))
	return h.Sum64() % numberOfStatsBucketsToCoarsenTo
}

func bucketInt64(toHash int64) uint64 {
	h := fnv.New64a()
	h.Write([]byte(fmt.Sprintf("%d", toHash)))
	return h.Sum64() % numberOfStatsBucketsToCoarsenTo
}

// exceptionTags returns a map of key-value pairs that can be
// attached to exception events to provide context about the request.
// The keys are prefixed with `#` are indexed by Sentry.
// The HTTP request `r` is optional and can be `nil` - if present,
// fields from the request like method/path will be included.
func exceptionTags(ctx context.Context, r *http.Request) map[string]string {
	tags := map[string]string{}

	requestID := requestid.GetGitHubRequestID(ctx)
	if requestID != "" {
		tags["#request_id"] = requestID
	}

	hydroMsg, ok := HydroMessage(ctx)
	if ok {
		tags["#hydro.envelope_id"] = hydroMsg.EnvelopeId
		tags["hydro.topic"] = hydroMsg.Topic
		tags["hydro.partition"] = fmt.Sprintf("%d", hydroMsg.Partition)
		tags["hydro.offset"] = fmt.Sprintf("%d", hydroMsg.Offset)
	}

	aqueductJob, ok := AqueductJob(ctx)
	if ok {
		tags["aqueduct.queue"] = aqueductJob.Queue
		if aqueductJob.ID != "" {
			tags["aqueduct.job.id"] = aqueductJob.ID
		}
	}

	user, hasUser := User(ctx)
	if hasUser {
		tags["#gh.actor.id"] = fmt.Sprintf("%d", user.ID)
		if user.TokenInfo != nil {
			tags["#gh.actor.integration_id"] = fmt.Sprintf("%d", user.TokenInfo.ApplicationID)
			tags["#gh.actor.integration_type"] = user.TokenInfo.ApplicationType
		}
	}

	repo, ok := Repo(ctx)
	if ok {
		tags["#repo.id"] = fmt.Sprintf("%d", repo.ID)
	}

	issue, ok := Issue(ctx)
	if ok {
		tags["#issue.id"] = fmt.Sprintf("%d", issue.ID)
		tags["#issue.number"] = fmt.Sprintf("%d", issue.Number)
	}

	pr, ok := PullRequest(ctx)
	if ok {
		tags["#pr.number"] = fmt.Sprintf("%d", pr.Number)
		if pr.ID != nil {
			tags["#pr.id"] = fmt.Sprintf("%d", *pr.ID)
		}
		if pr.ReviewID != nil {
			tags["#pr.review_id"] = fmt.Sprintf("%d", *pr.ReviewID)
		}
		if pr.CommentID != nil {
			tags["#pr.comment_id"] = fmt.Sprintf("%d", *pr.CommentID)
		}
	}

	run, ok := WorkflowRun(ctx)
	if ok {
		tags["#workflow_run.id"] = fmt.Sprintf("%d", run.ID)
		if run.JobID != nil {
			tags["#workflow_run.job_id"] = fmt.Sprintf("%d", *run.JobID)
		}
	}

	job, ok := Job(ctx)
	if ok {
		tags["#job.id"] = job.ID
		tags["#job.repo_id"] = fmt.Sprintf("%d", job.RepoID)
		tags["#job.assignment_id"] = job.AssignmentID
		if job.ComputeID != "" {
			tags["#job.compute_id"] = job.ComputeID
		}
		if job.SessionID != "" {
			tags["#job.session_id"] = job.SessionID
		}
		if job.EventType != "" {
			tags["#job.event_type"] = job.EventType
		}
		// override the user used to group exceptions with the job actor if it isn't
		// already set by the user in the context. This ensures the user is set to
		// the the issue assigner or PR reviewer/commenter, and falls back to the
		// user that triggered the job if the actor is not set (is an app or copilot).
		if !hasUser && job.ActorID != 0 {
			tags["#gh.actor.id"] = fmt.Sprintf("%d", job.ActorID)
		}

		if job.CustomAgent.RepoID != 0 {
			tags["#job.custom_agent.repo_id"] = fmt.Sprintf("%d", job.CustomAgent.RepoID)
		}
		if job.CustomAgent.OwnerID != 0 {
			tags["#job.custom_agent.owner_id"] = fmt.Sprintf("%d", job.CustomAgent.OwnerID)
		}
		if job.CustomAgent.Name != "" {
			tags["job.custom_agent.name"] = job.CustomAgent.Name
		}
	}

	session, ok := Session(ctx)
	if ok {
		if session.ID != "" {
			tags["#session.id"] = session.ID
		}
		if session.State != "" {
			tags["#session.state"] = session.State
		}
		if session.ResourceType != "" {
			tags["#session.resource_type"] = session.ResourceType
		}
		if session.ResourceID != 0 {
			tags["#session.resource_id"] = fmt.Sprintf("%d", session.ResourceID)
		}
		if session.EventType != "" {
			tags["#session.event_type"] = session.EventType
		}
		if session.WorkflowRunID != 0 {
			tags["#session.workflow_run_id"] = fmt.Sprintf("%d", session.WorkflowRunID)
		}
	}

	alerts, ok := CodeScanningAlerts(ctx)
	if ok {
		tags["#alert.repo_id"] = fmt.Sprintf("%d", alerts.RepoID)
		tags["#alert.actor_id"] = fmt.Sprintf("%d", alerts.ActorID)
		tags["#alert.numbers"] = fmt.Sprintf("%v", alerts.AlertNumbers)
	}

	ps, ok := ProblemStatement(ctx)
	if ok {
		if ps.Source != "" {
			tags["#problem_statement.source"] = ps.Source
		}
	}

	if r != nil {
		tags["method"] = r.Method
		tags["url"] = r.URL.String()
		tags["route"] = ghchi.Route(r)
		tags["#user_agent"] = r.UserAgent()
	}

	// Not adding experimentation service object here. This shows up in sentry and should not result in pages

	return tags
}

// logFields returns a list of key-value pairs that can be
// attached to log events to provide context about the request.
// The HTTP request `r` is optional and can be `nil` - if present,
// fields from the request like method/path will be included.
func logFields(ctx context.Context, r *http.Request) []kvp.Field {
	kvps := []kvp.Field{}

	requestID := requestid.GetGitHubRequestID(ctx)
	if requestID != "" {
		kvps = append(kvps, kvp.String("gh.request_id", requestID))
	}

	user, hasUser := User(ctx)
	if hasUser {
		kvps = append(kvps,
			kvp.Uint64("gh.actor.id", user.ID),
			kvp.String("gh.actor.tracking_id", user.TrackingID),
		)
		if user.TokenInfo != nil {
			kvps = append(kvps,
				kvp.Uint64("gh.actor.integration_id", user.TokenInfo.ApplicationID),
				kvp.String("gh.actor.integration_type", user.TokenInfo.ApplicationType),
			)
		}
	}

	hydroMsg, ok := HydroMessage(ctx)
	if ok {
		kvps = append(kvps,
			kvp.String("hydro.envelope_id", hydroMsg.EnvelopeId),
			kvp.String("hydro.topic", hydroMsg.Topic),
			kvp.Int32("hydro.partition", hydroMsg.Partition),
			kvp.Int64("hydro.offset", hydroMsg.Offset),
		)
	}

	aqueductJob, ok := AqueductJob(ctx)
	if ok {
		kvps = append(kvps, kvp.String("aqueduct.queue", aqueductJob.Queue))
		if aqueductJob.ID != "" {
			kvps = append(kvps, kvp.String("aqueduct.job.id", aqueductJob.ID))
		}
		kvps = append(kvps, kvp.Int32("aqueduct.job.requeue_count", aqueductJob.RequeueCount))
	}

	repo, ok := Repo(ctx)
	if ok {
		kvps = append(kvps,
			kvp.Int64("gh.repo.id", repo.ID),
			kvp.Int64("gh.repo.owner_id", repo.OwnerID),
		)
	}

	issue, ok := Issue(ctx)
	if ok {
		kvps = append(kvps,
			kvp.Int64("gh.issue.id", issue.ID),
			kvp.Int("gh.issue.number", issue.Number),
		)
	}

	pr, ok := PullRequest(ctx)
	if ok {
		kvps = append(kvps, kvp.Int("gh.pr.number", pr.Number))
		if pr.ID != nil {
			kvps = append(kvps, kvp.Int64("gh.pr.id", *pr.ID))
		}
		if pr.ReviewID != nil {
			kvps = append(kvps, kvp.Int64("gh.pr.review_id", *pr.ReviewID))
		}
		if pr.CommentID != nil {
			kvps = append(kvps, kvp.Int64("gh.pr.comment_id", *pr.CommentID))
		}
		if pr.State != "" {
			kvps = append(kvps, kvp.String("gh.pr.state", pr.State))
		}
	}

	run, ok := WorkflowRun(ctx)
	if ok {
		kvps = append(kvps, kvp.Int64("gh.workflow_run.id", run.ID))
		if run.JobID != nil {
			kvps = append(kvps, kvp.Int64("gh.workflow_run.job_id", *run.JobID))
		}
	}

	job, ok := Job(ctx)
	if ok {
		kvps = append(kvps,
			kvp.String("job.id", job.ID),
			kvp.Int64("job.repo_id", job.RepoID),
			kvp.Int64("job.owner_id", job.OwnerID),
			kvp.String("job.assignment_id", job.AssignmentID),
		)
		if job.ComputeID != "" {
			kvps = append(kvps, kvp.String("job.compute_id", job.ComputeID))
		}
		if job.SessionID != "" {
			kvps = append(kvps, kvp.String("job.session_id", job.SessionID))
		}
		if job.EventType != "" {
			kvps = append(kvps, kvp.String("job.event_type", job.EventType))
		}
		if job.ActorID != 0 {
			kvps = append(kvps, kvp.Int64("job.actor_id", job.ActorID))
		}
		if job.PullRequestID != 0 {
			kvps = append(kvps, kvp.Int64("job.pull_request.id", job.PullRequestID))
		}
		if job.PullRequestNumber != 0 {
			kvps = append(kvps, kvp.Int("job.pull_request.number", job.PullRequestNumber))
		}

		// this format is mainly regarding the log output in splunk, so it should be human readable
		if job.CreatedAt != 0 {
			kvps = append(kvps, kvp.String("job.created_at", time.Unix(job.CreatedAt, 0).Format(time.RFC3339)))
		}
		if job.CompletedAt != 0 {
			kvps = append(kvps, kvp.String("job.completed_at", time.Unix(job.CompletedAt, 0).Format(time.RFC3339)))
		}
		if job.QueuedAt != 0 {
			kvps = append(kvps, kvp.String("job.queued_at", time.Unix(job.QueuedAt, 0).Format(time.RFC3339)))
		}

		if job.Status != "" {
			kvps = append(kvps, kvp.String("job.status", job.Status))
		}
		if job.BranchName != "" {
			kvps = append(kvps, kvp.String("job.branch_name", job.BranchName))
		}

		if job.Experiments.Variations != nil {
			for k, v := range job.Experiments.Variations {
				kvps = append(kvps, kvp.Any(fmt.Sprintf("job.experiments.variations.%s", k), v))
			}
		}
		if job.Experiments.AssignmentContext != "" {
			kvps = append(kvps, kvp.String("job.experiments.assignment_context", job.Experiments.AssignmentContext))
		}

		if !hasUser && job.ActorID != 0 {
			kvps = append(kvps, kvp.Uint64("gh.actor.id", uint64(job.ActorID)))
		}

		// Custom agent data if present
		if job.CustomAgent.Name != "" {
			kvps = append(kvps, kvp.String("job.custom_agent.name", job.CustomAgent.Name))
		}
		if job.CustomAgent.OwnerID != 0 {
			kvps = append(kvps, kvp.Int64("job.custom_agent.owner_id", job.CustomAgent.OwnerID))
		}
		if job.CustomAgent.RepoID != 0 {
			kvps = append(kvps, kvp.Int64("job.custom_agent.repo_id", job.CustomAgent.RepoID))
		}
		if job.CustomAgent.Version != "" {
			kvps = append(kvps, kvp.String("job.custom_agent.version", job.CustomAgent.Version))
		}
	}

	session, ok := Session(ctx)
	if ok {
		if session.ID != "" {
			kvps = append(kvps, kvp.String("session.id", session.ID))
		}
		if session.State != "" {
			kvps = append(kvps, kvp.String("session.state", session.State))
		}
		if session.ResourceType != "" {
			kvps = append(kvps, kvp.String("session.resource_type", session.ResourceType))
		}
		if session.ResourceID != 0 {
			kvps = append(kvps, kvp.Int64("session.resource_id", session.ResourceID))
		}
		if session.EventType != "" {
			kvps = append(kvps, kvp.String("session.event_type", session.EventType))
		}
		if session.WorkflowRunID != 0 {
			kvps = append(kvps, kvp.Uint64("session.workflow_run_id", session.WorkflowRunID))
		}
	}

	update, ok := JobUpdate(ctx)
	if ok {
		if update.Kind != "" {
			kvps = append(kvps, kvp.String("job.update.kind", update.Kind))
		}
		if update.Action != "" {
			kvps = append(kvps, kvp.String("job.update.action", update.Action))
		}
		if update.CreatedAt != 0 {
			kvps = append(kvps, kvp.String("job.update.created_at", time.Unix(update.CreatedAt, 0).Format(time.RFC3339)))
		}
	}

	alerts, ok := CodeScanningAlerts(ctx)
	if ok {
		kvps = append(kvps,
			kvp.Int64("alert.repo_id", alerts.RepoID),
			kvp.Int64("alert.owner_id", alerts.OwnerID),
			kvp.Int64("alert.actor_id", alerts.ActorID),
			kvp.Strings("alert.assignees", alerts.Assignees),
			kvp.Int64s("alert.numbers", alerts.AlertNumbers),
		)
	}

	ps, ok := ProblemStatement(ctx)
	if ok {
		kvps = append(kvps,
			kvp.Bool("problem_statement.removed_comments", ps.RemovedComments),
			kvp.Bool("problem_statement.truncated_comments", ps.TruncatedComments),
			kvp.Bool("problem_statement.truncated_description", ps.TruncatedDescription),
		)

		if ps.Length != 0 {
			kvps = append(kvps, kvp.Int("problem_statement.length", ps.Length))
		}
		if ps.Base64Length != 0 {
			kvps = append(kvps, kvp.Int("problem_statement.length_base64", ps.Base64Length))
		}
		if ps.Source != "" {
			kvps = append(kvps, kvp.String("problem_statement.source", ps.Source))
		}
		if ps.RemovedCommentsCount != 0 {
			kvps = append(kvps, kvp.Int("problem_statement.removed_comments_count", ps.RemovedCommentsCount))
		}
	}

	if r != nil {
		kvps = append(kvps,
			kvp.String("http.request.method", r.Method),
			kvp.String("url.path", r.URL.Path),
			kvp.String("url.route", ghchi.Route(r)),
			kvp.String("user_agent.original", r.UserAgent()),
			kvp.String("http.request.header.real_ip", r.Header.Get("X-Real-IP")),
		)
	}

	return kvps
}

// AddCopilotUserDetails adds CopilotUserDetails to the request context for a specific user ID.
func AddCopilotUserDetails(ctx context.Context, userID int64, userDetails *copilotUsersTwirp.CopilotUserDetails) error {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return fmt.Errorf("requestctx: context does not contain requestContext")
	}
	if d.CopilotUserDetailsCache == nil {
		d.CopilotUserDetailsCache = make(map[int64]*copilotUsersTwirp.CopilotUserDetails)
	}
	d.CopilotUserDetailsCache[userID] = userDetails
	return nil
}

// CopilotUserDetails returns the CopilotUserDetails from the request context for a specific user ID.
func CopilotUserDetails(ctx context.Context, userID int64) (*copilotUsersTwirp.CopilotUserDetails, bool) {
	d, ok := ctx.Value(reqCtxKey).(*CtxData)
	if !ok {
		return nil, false
	}
	if d.CopilotUserDetailsCache == nil {
		return nil, false
	}
	userDetails, ok := d.CopilotUserDetailsCache[userID]
	return userDetails, ok
}

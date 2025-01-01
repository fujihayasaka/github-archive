/*
Package github implements a GraphQL client capable of querying both the internal and public GitHub API.

For information about GitHub's GraphQL API see https://thehub.github.com/engineering/development-and-ops/public-apis/graphql/using-graphiql/
*/
package github

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httputil"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/shurcooL/githubv4"
	"github.com/shurcooL/graphql"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/ratelimit"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	cu "github.com/github/launch/clients/utils"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/kvperrors"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/permitreplicas"
	"github.com/github/launch/utils/useragent"
)

const (
	graphqlQueryMaxRetries      = 3
	graphqlQueryRetryDelay      = 600 * time.Millisecond
	graphqlQueryRetryMultiplier = 2.0
	graphqlQueryRetryRandFactor = 0.5

	ErrorStatusValue = "error"
)

type graphQLRequest struct {
	Query     string         `json:"query"`
	Variables map[string]any `json:"variables,omitempty"`
}

// GraphQLResponse contains the results of a GraphQL query.
type GraphQLResponse struct {
	Data   any            `json:"data"`
	Errors []GraphQLError `json:"errors"`
}

// GraphQLError contains data relating to validation errors in a GraphQL query.
type GraphQLError struct {
	Message string `json:"message"`
	Type    string `json:"type,omitempty"`
}

func (e GraphQLError) Error() string {
	return "error from API: " + e.Message
}

type ModifiedFiles struct {
	Paths []string
}

type gqlRunner interface {
	// do executes the request, given a context, a GraphQL query string, and the destination object.
	do(ctx context.Context, opname, optype, query string, variables map[string]any, dest any, optionalHeaders http.Header) (*GraphQLResponse, error)
}

// Client provides an interface for making requests to the GitHub GraphQL API.
type Client interface {
	gqlRunner

	ResolveDefaultBranch(ctx context.Context, repositoryID types.GlobalID) (types.CommitSha, types.GitRef, error)
	ResolveRef(ctx context.Context, repositoryID types.GlobalID, ref types.GitRef, opts ...ResolveRefOption) (types.CommitSha, types.GitRef, error)

	RepositoryNWO(ctx context.Context, repositoryID types.GlobalID) (types.RepositoryFullName, error)
	RepositoryInfoFromID(ctx context.Context, id types.GlobalID) (*BasicRepositoryInfo, error)
	CreateCheckSuite(ctx context.Context, req CreateCheckSuiteRequest) (*CreateCheckSuiteResponse, error)
	CreateCheckRun(ctx context.Context, req CreateCheckRunRequest) (CheckRunResponse, error)
	UpdateCheckRun(ctx context.Context, req UpdateCheckRunRequest) (CheckRunResponse, error)
	UpdateCheckSuite(ctx context.Context, req UpdateCheckSuiteRequest) (*types.IDPair, error)
	GetDataForWorkflowInvocation(ctx context.Context, repositoryID types.GlobalID, commit types.CommitSha, actorID types.GlobalID, pipelinesDirectory string) (*types.WorkflowInvocationData, error)
	GetReportingMetadata(ctx context.Context, repositoryID types.GlobalID, actorID types.GlobalID) (metadata.WorkflowMetadata, error)
	GetRepositoryScheduleData(ctx context.Context, repoNodeID types.GlobalID, branchRef types.GitRef, actorNodeID types.GlobalID, env launchconfig.AppEnv) (*RepositoryScheduleData, error)
	GetCurrentScheduleState(ctx context.Context, repoGID types.GlobalID, env launchconfig.AppEnv) (*RepositoryScheduleState, error)

	GetCheckSuiteFromDotcom(ctx context.Context, checkSuiteID types.GlobalID) (*CheckSuiteInfo, error)

	// GetMergeStatusForPullRequest will return the merge commit and whether the referenced PR is considered mergeable
	GetMergeStatusForPullRequest(ctx context.Context, repoGID types.GlobalID, prNumber int) (*PullRequestMergeState, error)

	// GetFilterDiff identifies a set of changed paths for a specific event
	GetFilterDiff(ctx context.Context, repoGID types.GlobalID, headBase types.BeforeAfterSHA, ref types.GitRef, pullIDMaybe types.GlobalID) (*FilterDiffResult, error)

	// CheckCommitReachability determines whether the commit OID is in a branch or tag
	CheckCommitReachability(ctx context.Context, repoGID types.GlobalID, commitOID types.CommitSha) (*bool, error)

	// GetEnvironment gets environment information
	GetEnvironment(ctx context.Context, repoID types.GlobalID, environmentName string) (*EnvironmentResponse, error)

	// CreateEnvironment creates an environment with idempotency
	CreateEnvironment(ctx context.Context, repoID types.GlobalID, environmentName string) (*EnvironmentResponse, error)

	CreateGateRequest(ctx context.Context, req CreateGateRequestRequest) (*types.IDPair, error)

	GetSecretPolicies(ctx context.Context, repoID types.GlobalID) (*SecretPolicies, error)

	GetPolicies(ctx context.Context, repoID types.GlobalID) (*Policies, error)

	IsRefProtected(ctx context.Context, repositoryID types.GlobalID, ref types.GitRef, opts ...ResolveRefOption) (bool, error)

	ReusePreviousWorkflowRun(ctx context.Context, req ReusePreviousWorkflowRequest) (*ReusePreviousWorkflowRunResponse, error)
}

type Options struct {
	defaultRequestHeaders map[string]string
}
type Option func(*Options)

func WithNextGlobalIDHeader() Option {
	return func(o *Options) {
		// Don't send the header to Enterprise. See https://github.com/github/ecosystem-api/issues/3306
		headerEnabled := launchconfig.UsingNextGIDs()
		if headerEnabled {
			o.defaultRequestHeaders["X-Github-Next-Global-Id"] = "1"
		}
	}
}

type client struct {
	env                   launchconfig.AppEnv
	apiURLs               cu.GraphQLURLProvider
	gqlClient             *githubv4.Client
	serviceToken          tokens.ServiceToken
	token                 *tokens.AccessToken
	httpClient            *ahttp.Client
	obs                   *observability.Observability
	timeNow               func() time.Time
	hooks                 *ClientHooks
	isMultiTenant         bool
	defaultRequestHeaders map[string]string
	GHTwirpClient         ghtwirp.Client
}

func newClient(
	env launchconfig.AppEnv,
	apiURLs cu.GraphQLURLProvider,
	gqlClient *githubv4.Client,
	serviceToken tokens.ServiceToken,
	token *tokens.AccessToken,
	httpClient *ahttp.Client,
	obs *observability.Observability,
	timeNow func() time.Time,
	hooks *ClientHooks,
	isMultiTenant bool,
	GHTwirpClient ghtwirp.Client,
	options ...Option,
) *client {
	hooks.ensureDefaults()

	opts := &Options{
		defaultRequestHeaders: map[string]string{},
	}

	for _, option := range options {
		option(opts)
	}
	return &client{
		env:                   env,
		apiURLs:               apiURLs,
		gqlClient:             gqlClient,
		serviceToken:          serviceToken,
		token:                 token,
		httpClient:            httpClient,
		obs:                   obs,
		timeNow:               timeNow,
		hooks:                 hooks,
		isMultiTenant:         isMultiTenant,
		defaultRequestHeaders: opts.defaultRequestHeaders,
		GHTwirpClient:         GHTwirpClient,
	}
}

// setPermitReplicasHeader sets the X-PermitReplicas header to true.
func (c *client) setPermitReplicasHeader(header http.Header) http.Header {
	if header == nil {
		header = make(http.Header)
	}
	header.Set(permitreplicas.PermitReplicasHeader, "1")

	return header
}

// setSerializeLoginHeader sets the X-Serialize-Login header to the given serializer mode if the client is in multi-tenant mode,
// otherwise it does nothing.
func (c *client) setSerializeLoginHeader(header http.Header, serializerMode string) http.Header {

	if c.isMultiTenant {
		header.Set(ghtenant.SerializeLoginHeader, serializerMode)
	}

	return header
}

func (c *client) withAuthenticatedRequest(ctx context.Context) graphql.RequestOption {
	return func(req *http.Request) error {
		ctx, span := tracing.Start(ctx)
		defer span.End()

		req.Header.Set("User-Agent", useragent.GetUserAgent(c.env.String()))
		req = req.WithContext(ctx)
		mu.ForwardRequestID(req)

		err := ghtenant.ForwardGitHubTenant(req, c.isMultiTenant, c.obs.Logger)
		if err != nil {
			return tracing.RecordError(span, errors.Wrap(err, "Failed to set Tenant header"))
		}

		if c.token != nil {
			req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))
		}
		if c.serviceToken != tokens.NullServiceToken {
			req.Header.Set("GitHub-Internal-GraphQL-Token", c.serviceToken.String())
		}

		req.Header.Set("GraphQL-Schema", "internal")
		req.Header.Set("GraphQL-Features", "actions_graphql_cd,merge_queue")

		for k, v := range c.defaultRequestHeaders {
			req.Header.Set(k, v)
		}

		return nil
	}
}

func (c *client) withOptionalHeaders(optionalHeaders http.Header) graphql.RequestOption {
	return func(req *http.Request) error {
		if optionalHeaders == nil {
			return nil
		}

		for k, v := range optionalHeaders {
			req.Header[k] = v
		}

		return nil
	}
}

func (c *client) newRequest(ctx context.Context, request *graphQLRequest, optionalHeaders http.Header) (*http.Request, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	jsonData, err := json.Marshal(request)
	if err != nil {
		return nil, tracing.RecordError(span, kvperrors.WrapWith(err))
	}

	req, err := http.NewRequest(http.MethodPost, c.apiURLs.GraphQLApiURL(), bytes.NewReader(jsonData))
	if err != nil {
		return req, tracing.RecordError(span, kvperrors.WrapWith(err))
	}

	req.Header.Set("User-Agent", useragent.GetUserAgent(c.env.String()))

	req = req.WithContext(ctx)
	mu.ForwardRequestID(req)
	req.Header.Set("Content-Type", "application/json")

	// Add the tenant header to all of our GraphQL requests
	err = ghtenant.ForwardGitHubTenant(req, c.isMultiTenant, c.obs.Logger)
	if err != nil {
		return req, tracing.RecordError(span, kvperrors.WrapWith(err))
	}

	if c.token != nil {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.token))
	}

	if c.serviceToken != tokens.NullServiceToken {
		req.Header.Set("GitHub-Internal-GraphQL-Token", c.serviceToken.String())
	}

	req.Header.Set("GraphQL-Schema", "internal")
	req.Header.Set("GraphQL-Features", "actions_graphql_cd,merge_queue")

	for k, v := range c.defaultRequestHeaders {
		req.Header.Set(k, v)
	}

	for k, v := range optionalHeaders {
		req.Header[k] = v
	}

	return req, nil
}

func (c *client) parseResponse(resp *http.Response, dest any, qi *queryDebugInfo) (*GraphQLResponse, error) {
	r := &GraphQLResponse{Data: dest}

	decoder := json.NewDecoder(resp.Body)
	if err := decoder.Decode(r); err != nil {
		return nil, kvperrors.WrapWith(errors.Wrap(err, "error parsing GQL response"),
			kvp.String("graphql.operation.name", fmt.Sprintf("%T", err)),
			qi.reqKVP(),
		)
	}
	return r, nil
}

// dest should be the shape of the body without the top level `data:` wrapper.
func (c *client) do(ctx context.Context, opname, optype, query string, variables map[string]any, dest any, optionalHeaders http.Header) (*GraphQLResponse, error) {
	ctx, span := tracing.Start(ctx, trace.WithAttributes(
		attribute.String("graphql.operation.name", opname),
		attribute.String("graphql.operation.type", optype),
	))
	defer span.End()

	start := c.timeNow()
	c.hooks.OnBeginRPC(ctx, opname, optype)

	attempt := 0
	res := &RPCResult{Status: "incomplete", Attempt: attempt}
	defer func() {
		res.Duration = c.timeNow().Sub(start)
		c.hooks.OnEndRPC(ctx, opname, optype, res)
	}()

	var (
		gqlResponse *GraphQLResponse
		statusCode  int
	)

	// allow the API to attempt to read from replicas if the caller opts in
	optionalHeaders = c.setPermitReplicasHeader(optionalHeaders)

	err := c.withRetries(ctx, opname, optype, func(ctx context.Context) error {
		attempt++
		res.Attempt = attempt
		var err error

		gqlResponse, statusCode, err = c.doOnce(ctx, opname, optype, query, variables, &dest, attempt, optionalHeaders)
		if terrors.IsNotFoundError(err) || terrors.IsForbiddenError(err) {
			// Remove the permit replicas header to allow the API to attempt to read from the primary
			// in case the cause of the retry was not found due to replication lag.
			optionalHeaders.Del(permitreplicas.PermitReplicasHeader)
		}
		if errors.Cause(err) == circuit.ErrBreakerOpen {
			// Note: We retry on terrors.IsNotFoundError(errors.Cause(err)) as well since in the past we have seen replication lags
			err = backoff.Permanent(err)
		}
		return tracing.RecordError(span, err)
	})
	res.Code = statusCode
	res.Status = resultStatus(err)
	return gqlResponse, tracing.RecordError(span, err)
}

// strictQuery wraps the underlying GraphQL client's Query function so we can
// perform things like recording metrics/stats and differentiate between all of
// our requests.
func (c *client) strictQuery(ctx context.Context, opname, optype string, q any, variables map[string]any) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	start := c.timeNow()
	c.hooks.OnBeginRPC(ctx, opname, optype)

	attempt := 0
	res := &RPCResult{Status: "incomplete", Attempt: attempt}
	defer func() {
		res.Duration = c.timeNow().Sub(start)
		c.hooks.OnEndRPC(ctx, opname, optype, res)
	}()

	err := c.withRetries(ctx, opname, optype, func(ctx context.Context) error {
		attempt++
		res.Attempt = attempt
		retryCtx, span := tracing.StartWithOpFuncName(ctx, "attemptMutation", trace.WithAttributes(
			attribute.String("graphql.operation.name", opname),
		))
		defer span.End()

		// TODO: no way to hook into the distinction between sending the request and reading the response
		// when delegating to the `gqlClient.Query` func...
		reqStart := c.timeNow()
		reqStats := &ReqResult{
			Status:  "incomplete",
			Attempt: attempt,
		}
		c.hooks.OnStartPerformRequest(ctx, opname, optype, attempt)
		defer func() {
			reqStats.Duration = c.timeNow().Sub(reqStart)
			c.hooks.OnDonePerformRequest(ctx, opname, optype, reqStats)
		}()

		respStart := c.timeNow()
		respStats := &RespResult{Status: "incomplete", Attempt: attempt}
		c.hooks.OnStartHandleResponse(ctx, opname, optype)
		defer func() {
			respStats.Duration = c.timeNow().Sub(respStart)
			c.hooks.OnDoneHandleResponse(ctx, opname, optype, respStats)
			span.SetAttributes(
				attribute.String("http.response.status", respStats.Status),
				attribute.Int("http.response.status_code", respStats.Code),
			)
		}()

		err := c.gqlClient.Query(retryCtx, q, variables, c.withAuthenticatedRequest(retryCtx))

		reqStats.Status = resultStatus(err)
		reqStats.Err = err
		respStats.Status = resultStatus(err)
		if err == nil {
			// the gqlclient.Query does not give us an actual http response back, so lets infer success if we didn't see an error
			respStats.Code = 200
		}
		respStats.Err = err

		return tracing.RecordError(span, err)
	})
	res.Status = resultStatus(err)
	if err != nil {
		graphQLError := convertGraphQLError(err)
		return tracing.RecordError(span, graphQLError)
	}
	return nil
}

// mutate wraps the underlying GraphQL client's mutate function so we can
// perform things like recording metrics/stats and differentiate between all of
// our requests.
func (c *client) mutate(ctx context.Context, opname string, m any, input githubv4.Input, variables map[string]any, optionalHeaders http.Header) error {

	ctx, span := tracing.Start(ctx)
	defer span.End()

	optype := "mutation"
	start := c.timeNow()
	c.hooks.OnBeginRPC(ctx, opname, optype)

	attempt := 0
	res := &RPCResult{Status: "incomplete", Attempt: attempt}
	defer func() {
		res.Duration = c.timeNow().Sub(start)
		c.hooks.OnEndRPC(ctx, opname, optype, res)
	}()

	// allow the API to attempt to read from replicas if the caller opts in
	optionalHeaders = c.setPermitReplicasHeader(optionalHeaders)

	err := c.withRetries(ctx, opname, optype, func(ctx context.Context) error {
		retryCtx, span := tracing.StartWithOpFuncName(ctx, "attemptMutation", trace.WithAttributes(
			attribute.String("graphql.operation.name", opname),
		))
		defer span.End()

		attempt++

		// TODO: no way to hook into the distinction between sending the request and reading the response
		// when delegating to the `gqlClient.Mutate` func...
		reqStart := c.timeNow()
		reqStats := &ReqResult{
			Status:  "incomplete",
			Attempt: attempt,
		}
		c.hooks.OnStartPerformRequest(ctx, opname, optype, attempt)
		defer func() {
			reqStats.Duration = c.timeNow().Sub(reqStart)
			c.hooks.OnDonePerformRequest(ctx, opname, optype, reqStats)
		}()

		respStart := c.timeNow()
		respStats := &RespResult{Status: "incomplete", Attempt: attempt}
		c.hooks.OnStartHandleResponse(ctx, opname, optype)
		defer func() {
			respStats.Duration = c.timeNow().Sub(respStart)
			c.hooks.OnDoneHandleResponse(ctx, opname, optype, respStats)
		}()

		err := c.gqlClient.Mutate(retryCtx, m, input, variables, c.withAuthenticatedRequest(retryCtx), c.withOptionalHeaders(optionalHeaders))
		graphQLError := convertGraphQLError(err)
		if terrors.IsNotFoundError(graphQLError) || terrors.IsForbiddenError(graphQLError) {
			// Remove the permit replicas header to allow the API to attempt to read from the primary
			// in case the cause of the retry was not found due to replication lag.
			optionalHeaders.Del(permitreplicas.PermitReplicasHeader)
		}

		reqStats.Status = resultStatus(err)
		reqStats.Err = err
		respStats.Status = resultStatus(err)
		respStats.Err = err
		if err == nil {
			// the gqlclient.Mutate does not give us an actual http response back, so lets infer success if we didn't see an error
			respStats.Code = 200
		}

		return tracing.RecordError(span, err)
	})
	res.Status = resultStatus(err)
	if err != nil {
		graphQLError := convertGraphQLError(err)
		return tracing.RecordError(span, graphQLError)
	}

	return nil
}

func (c *client) doOnce(ctx context.Context, opname, optype, query string, variables map[string]any, dest any, attempt int, optionalHeaders http.Header) (*GraphQLResponse, int, error) {
	ctx, span := tracing.StartWithOpFuncName(ctx, "attempt",
		trace.WithAttributes(
			attribute.String("graphql.operation.name", opname),
			attribute.String("graphql.operation.type", optype),
		),
	)
	defer span.End()

	qv := &graphQLRequest{Query: query, Variables: variables}

	req, err := c.newRequest(ctx, qv, optionalHeaders)
	if err != nil {
		return nil, -1, terrors.NewGraphQLError(errors.Wrap(err, "error creating graphql request"))
	}

	qi := &queryDebugInfo{}
	qi.setRequest(req)

	c.hooks.OnStartPerformRequest(ctx, opname, optype, attempt)
	reqStats := &ReqResult{Status: "incomplete"}

	reqStart := c.timeNow()
	resp, err := c.httpClient.Do(req)
	reqStats.Duration = c.timeNow().Sub(reqStart)
	reqStats.Status = resultStatus(err)
	c.hooks.OnDonePerformRequest(ctx, opname, optype, reqStats)
	if err != nil {
		return nil, -1, terrors.NewGraphQLError(errors.Wrap(err, "error making http request"))
	}
	defer resp.Body.Close()

	respStart := c.timeNow()
	respStats := &RespResult{Status: "incomplete", Attempt: attempt}
	c.hooks.OnStartHandleResponse(ctx, opname, optype)
	defer func() {
		respStats.Duration = c.timeNow().Sub(respStart)
		c.hooks.OnDoneHandleResponse(ctx, opname, optype, respStats)
		span.SetAttributes(
			attribute.String("http.response.status", respStats.Status),
			attribute.Int("http.response.status_code", respStats.Code),
		)
		span.SetAttributes()
	}()

	respStats.Code = resp.StatusCode
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		respStats.Status = "non_http_success_error"
		resp.Body.Close()

		if ratelimit.RateLimited(resp.StatusCode, resp.Header) {
			ratelimit.ReportRateLimiting(ctx, c.obs, resp, opname, true)

			return nil, resp.StatusCode, kvperrors.WrapWith(
				ratelimit.ErrorFromResponse(resp),
			)
		}

		return nil, resp.StatusCode, terrors.NewGraphQLError(kvperrors.WrapWith(
			errors.Errorf("unexpected response code from graphql %s", resp.Status),
		))
	}

	gqlResponse, err := c.parseResponse(resp, dest, qi)
	if err != nil {
		respStats.Status = "parseerror"
		respStats.Err = err
		return nil, resp.StatusCode, terrors.NewGraphQLError(err)
	}

	err = errorsFromResponse(gqlResponse)
	if err != nil {
		respStats.Status = "gqlerror"
		respStats.Err = err
		return gqlResponse, resp.StatusCode, terrors.NewGraphQLError(err)
	}

	respStats.Status = resultStatus(err)
	respStats.Err = err

	return gqlResponse, resp.StatusCode, nil
}

type queryDebugInfo struct {
	dreq       []byte
	authHeader string
}

func (qi *queryDebugInfo) setRequest(req *http.Request) {
	qi.authHeader = req.Header.Get("Authorization")
	dreq, err := httputil.DumpRequestOut(req, true)
	if err != nil {
		dreq = []byte(err.Error())
	} else {
		// split headers and rest.
		parts := bytes.SplitN(dreq, []byte("\r\n\r\n"), 2)
		if len(parts) == 2 {
			// get the request line.
			otherparts := bytes.Split(dreq, []byte("\r\n"))
			// drop all the headers. at least two lines are sensitive (installation token and service graphql token). just leave out all of the headers when logging this, they're not interesting anyway.
			dreq = append(append(otherparts[0], []byte("\r\n\r\n")...), parts[1]...)
		}
	}
	qi.dreq = dreq
	qi.authHeader = req.Header.Get("Authorization")
}

func (qi *queryDebugInfo) reqKVP() kvp.Field {
	return kvp.String("gh.launch.graphql_request", string(qi.dreq))
}

type RepositoryScheduleData struct {
	// e.g refs/heads/master
	DefaultBranchFullRef string
	ActorLogin           string
	ActorGID             types.GlobalID

	RepositoryScheduleState
}

type RepositoryScheduleState struct {
	CurrentHeadSHA   types.CommitSha
	PipelineFiles    []types.ResolvedFile
	ActionsPlanOwner types.GlobalID
	FullName         types.RepositoryFullName

	WorkflowFeatureFlags types.WorkflowFeatureFlags
}

func (c *client) withRetries(ctx context.Context, opname, optype string, f func(ctx context.Context) error) error {
	delay := backoff.NewExponentialBackOff()
	delay.InitialInterval = graphqlQueryRetryDelay
	delay.Multiplier = graphqlQueryRetryMultiplier
	delay.RandomizationFactor = graphqlQueryRetryRandFactor
	b := backoff.WithMaxRetries(delay, graphqlQueryMaxRetries)

	attempt := 0
	wrappedF := func() error {
		ctx, span := tracing.StartWithOpFuncName(ctx, "attempt",
			trace.WithAttributes(
				attribute.Int("http.request.resend_count", attempt),
				attribute.String("graphql.operation.name", opname),
				attribute.String("graphql.operation.type", optype),
			),
		)
		defer span.End()

		attempt++
		return f(ctx)
	}
	return backoff.Retry(wrappedF, b)
}

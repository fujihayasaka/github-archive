package prejobtoken

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/go-chi/chi"
	"github.com/pkg/errors"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"
	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/freno"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/clients/varz"
	"github.com/github/launch/constants"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/metrickeys"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/services/auth/hkdf"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/services/pb/deploy/token"
	tk "github.com/github/launch/services/pb/deploy/token"
	"github.com/github/launch/services/receiver"
	"github.com/github/launch/types"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/requestid"
)

const (
	maxReplicationWait = 30 * time.Second
)

var _ mu.Servicer = (*Servicer)(nil)

type Servicer struct {
	obs                  *observability.Observability
	log                  logger.Logger
	stats                statter.Statter
	verifier             hkdf.Verifier
	workflowbuildsRepo   deployer.WorkflowBuildsRepository
	ghTwirpClient        ghtwirp.Client
	tokenTwirpService    tk.LaunchTokenService
	deployerTwirpService deploy.LaunchDeploymentService
	receiverURL          string
	isLab                bool
	kredzClient          kredz.Client
	varzClient           varz.Client
	secretDecryptor      earthsmoke.Decryptor
	appRelayID           string
	frenoClient          freno.Client
	isEnterprise         bool
}

func NewServicer(
	obs *observability.Observability,
	log logger.Logger,
	stats statter.Statter,
	verifier hkdf.Verifier,
	workflowBuildsRepo deployer.WorkflowBuildsRepository,
	ghTwirpClient ghtwirp.Client,
	tokenTwirpService tk.LaunchTokenService,
	deployerTwirpService deploy.LaunchDeploymentService,
	receiverURL string,
	isLab bool,
	kredzClient kredz.Client,
	varzClient varz.Client,
	secretDecryptor earthsmoke.Decryptor,
	appRelayID string,
	frenoClient freno.Client,
	isEnterprise bool,
) *Servicer {
	return &Servicer{
		obs:                  obs,
		log:                  log,
		stats:                stats,
		verifier:             verifier,
		workflowbuildsRepo:   workflowBuildsRepo,
		ghTwirpClient:        ghTwirpClient,
		tokenTwirpService:    tokenTwirpService,
		deployerTwirpService: deployerTwirpService,
		receiverURL:          receiverURL,
		isLab:                isLab,
		kredzClient:          kredzClient,
		varzClient:           varzClient,
		secretDecryptor:      secretDecryptor,
		appRelayID:           appRelayID,
		frenoClient:          frenoClient,
		isEnterprise:         isEnterprise,
	}
}

const (
	tokenCreateRoute = `/actions/build/{workflowID:[0-9A-Za-z-]+}/jobs/{jobID}/pre_job_tokens`
)

type ServiceResponse struct {
	Token       string            `json:"token"`
	Permissions map[string]string `json:"permissions"`
	UsageCaps   UsageCaps         `json:"usage_caps"`
	ExpiresAt   string            `json:"expires_at"`
	// Secrets, if populated, are either Actions environment-level secrets or integration secrets for dynamic workflows.
	Secrets           map[string]string `json:"secrets,omitempty"`
	Variables         map[string]string `json:"variables,omitempty"`
	SendIDToken       bool              `json:"send_id_token"`
	EnvironmentNodeID types.GlobalID    `json:"environment_node_id,omitempty"`
}

type UsageCaps struct {
	CanRunJob         bool `json:"can_run_job"`
	CanCreateArtifact bool `json:"can_create_artifact"`
	BillingChecked    bool `json:"billing_checked"`
}

type prejobRequest struct {
	BareJobName     string            `json:"bare_job_name"`
	EnvironmentName string            `json:"environment_name"`
	Permissions     map[string]string `json:"permissions,omitempty"`
	IsHostedRunner  bool              `json:"is_hosted_runner"`
	ProductSKU      string            `json:"product_sku"`
}

func (s *Servicer) Routes() []mu.Route {
	return []mu.Route{
		mu.Post(tokenCreateRoute, s.HandleTokenCreate),
	}
}

//gocyclo:ignore
func (s *Servicer) HandleTokenCreate(resp http.ResponseWriter, req *http.Request) {
	ctx, span := tracing.Start(req.Context())
	defer span.End()
	reqStartTime := time.Now()

	if err := measurehttp.SetThreshold(ctx, thresholds.HTTPPreJobTokenLatency); err != nil {
		err := errors.Wrap(err, "couldn't find measurement struct in context")
		span.RecordError(err)
		http.Error(resp, "error getting measurement context", http.StatusInternalServerError)
		return
	}

	ctx = requestid.ForwardRequestIDToTwirp(ctx)

	mw.TagStatsWith(ctx, reqmeta.Tags{metrickeys.HTTPRoute: tokenCreateRoute})
	azpcorrelation.AddVSSCorrelationIDToSpan(ctx, span)

	workflowID := chi.URLParam(req, "workflowID")
	jobID := chi.URLParam(req, "jobID")

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.actions.plan_id", workflowID), kvp.String("gh.launch.job.id", jobID))

	respondWithError := func(code int, err error) {
		s.stats.Counter(ctx, "InvalidTokenRequest", nil, 1)
		s.log.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
		span.RecordError(err)
		http.Error(resp, http.StatusText(code), code)
	}

	data, err := io.ReadAll(req.Body)
	if err != nil {
		respondWithError(http.StatusBadRequest, errors.Wrap(err, "could not read http body"))
		return
	}

	if isValid, err := receiver.VerifySignature(s.verifier, req, data, s.receiverURL); err != nil {
		respondWithError(http.StatusBadRequest, err)
		return
	} else if !isValid {
		respondWithError(http.StatusUnauthorized, errors.New("Signature verification failed"))
		return
	}

	var pjr *prejobRequest
	if err := json.Unmarshal(data, &pjr); err != nil {
		err := errors.Wrap(err, "error unmarshalling request body")
		s.log.Report(ctx, err)
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	requestIDToken := pjr.Permissions["id_token"] == "write"
	delete(pjr.Permissions, "id_token")

	billingReq := deploy.GetWorkflowBillingDetailsRequest{
		WorkflowID:     workflowID,
		JobID:          jobID,
		IsHostedRunner: pjr.IsHostedRunner,
	}

	if pjr.ProductSKU != "" {
		billingReq.ProductSku = pjr.ProductSKU
	}

	workflowBillingResponse, err := s.deployerTwirpService.GetWorkflowBillingDetails(ctx, &billingReq)
	if err != nil {
		err := errors.Wrap(err, "error retrieving billing information")
		if terrors.IsTwirpError(err) {
			s.log.Report(ctx, err)
		}

		if terrors.IsNotFoundError(err) {
			respondWithError(http.StatusNotFound, err)
			return
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	// defer instead of calling now so that the ctx is as developed as possible
	defer s.recordBillingStat(ctx, workflowBillingResponse)
	repoGlobalID := types.IdentityToGlobalID(ctx, workflowBillingResponse.GetRepositoryId())

	if workflowBillingResponse.IsOwnerSpammy {
		s.log.Debug(ctx, "owner for repository is spammy", kvp.String("gh.repo.global_id", repoGlobalID.String()))
		respondWithError(http.StatusNotFound, errors.New("owner is spammy"))
		return
	}

	wb, err := s.fetchWorkflowBuild(ctx, workflowID, repoGlobalID)
	if err != nil {
		err := errors.Wrap(err, "error retrieving workflow build")
		if terrors.IsNotFoundError(err) {
			respondWithError(http.StatusNotFound, err)
			return
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}

	ctx = ctxstash.WithTags(ctx, stats.Tags{"customer_label": wb.data.CustomerLabel})
	token, err := s.makeTokenRequest(ctx, workflowID, jobID, wb, pjr)
	if err != nil {
		if svcerr.CallerShouldReportError(err) {
			s.log.Report(ctx, err)
		}
		if terrors.IsNotFoundError(err) {
			respondWithError(http.StatusNotFound, err)
			return
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}
	tokenReadableAt := time.Now()
	if frenoLag, err := s.frenoClient.Check(ctx, freno.InstallationTokensDBCluster); err != nil {
		s.obs.Report(ctx, errors.Wrap(err, "attempting to query freno lag"))
	} else {
		tokenReadableAt = tokenReadableAt.Add(frenoLag.ReplicationLag)
	}

	expiresAt := token.ExpiresAt.AsTime()

	var envSecrets map[string]string
	var variables map[string]string
	var environmentNodeID types.GlobalID
	environmentName := pjr.EnvironmentName
	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.repo.global_id", string(repoGlobalID)),
		kvp.String("gh.launch.prejob.environment_name", environmentName),
		kvp.Bool("gh.launch.prejob.request_id_token_present", requestIDToken))

	sendIDToken := false
	if environmentName != "" || requestIDToken {
		// Check security details for job that reference environment or try to get Id_Token
		securityReq := deploy.GetWorkflowSecurityDetailsRequest{
			WorkflowID: workflowID,
		}
		securityResponse, err := s.deployerTwirpService.GetWorkflowSecurityDetails(ctx, &securityReq)
		if err != nil {
			err := errors.Wrap(err, "error retrieving security details")
			if terrors.IsNotFoundError(err) {
				respondWithError(http.StatusNotFound, err)
				return
			}
			if terrors.IsTwirpError(err) {
				s.log.Report(ctx, err)
			}
			respondWithError(http.StatusInternalServerError, err)
			return
		}

		s.recordSecurityStat(ctx, securityResponse)

		environment, err := s.fetchEnvironment(ctx, environmentName, repoGlobalID, reqStartTime)
		if err != nil {
			err := errors.Wrap(err, "error retrieving environment information")
			s.log.Report(ctx, err)

			if terrors.IsNotFoundError(err) {
				respondWithError(http.StatusNotFound, err)
				return
			}

			respondWithError(http.StatusInternalServerError, err)
			return
		}

		if environment != nil {
			environmentNodeID = environment.GlobalID
		}

		envSecrets, err = s.fetchEnvironmentSecrets(ctx, environment, securityResponse)
		if err != nil {
			err := errors.Wrap(err, "error retrieving environment secrets")
			s.log.Report(ctx, err)

			if terrors.IsNotFoundError(err) {
				respondWithError(http.StatusNotFound, err)
				return
			}

			respondWithError(http.StatusInternalServerError, err)
			return
		}

		if s.isEnterprise || s.ghTwirpClient.IsFeatureEnabledForRepoOrOwners(ctx, github.ConfigurationVariablesEnabledFlag, repoGlobalID) {
			variables, err = s.fetchEnvironmentVariables(ctx, environment, securityResponse)
			if err != nil {
				err := errors.Wrap(err, "error retrieving environment variables")
				s.log.Report(ctx, err)

				if terrors.IsNotFoundError(err) {
					respondWithError(http.StatusNotFound, err)
					return
				}

				respondWithError(http.StatusInternalServerError, err)
				return
			}
		}

		if requestIDToken {
			if securityResponse.GetIsIDTokenGenerationAllowed() {
				sendIDToken = true
			} else {
				s.log.Log(ctx, "Id_Token not permitted")
			}
		}
	}

	integrationSecrets, err := s.fetchIntegrationSecrets(ctx, repoGlobalID, wb, pjr, reqStartTime)
	if err != nil {
		err := errors.Wrap(err, "error retrieving integration secrets")
		s.log.Report(ctx, err)

		if terrors.IsNotFoundError(err) {
			respondWithError(http.StatusNotFound, err)
			return
		}

		respondWithError(http.StatusInternalServerError, err)
		return
	}

	secrets := make(map[string]string)

	for k, v := range envSecrets {
		secrets[k] = v
	}

	// Integration secrets take precedence over all user-provided secrets. This is simpler than having integration
	// secrets precedence in between repository and environment secrets. Integrations may want to use secrets beginning
	// with the reserved prefix "GITHUB_"; see SECRET_KEY_RESERVED_PREFIX.
	for k, v := range integrationSecrets {
		secrets[k] = v
	}

	// We created tokens against the mysql primary, but queries for the token will come against the
	// replicas. To minimize the odds of tokens showing as invalid, we try to delay the enqueuing of
	// the build for the amount of replication lag.
	// See: https://github.com/github/c2c-actions-experience/issues/4170
	tokenReadableIn := time.Until(tokenReadableAt)
	s.emitResponseDelay(ctx, tokenReadableIn)
	if tokenReadableIn > 0 {
		s.obs.Debug(ctx, "Delaying pre_job_tokens response until token is readable", kvp.Duration("gh.launch.prejob.token.readable_in_sec", tokenReadableIn))

		select {
		case <-time.After(tokenReadableIn):
		case <-ctx.Done():
			s.log.Log(ctx, "timed out waiting for token to become readable",
				kvp.Duration("gh.launch.prejob.token.readable_in_sec", tokenReadableIn),
				kvp.Time("gh.launch.prejob.token.readable_at", tokenReadableAt),
			)
			retryAfter := strconv.Itoa(int(time.Until(tokenReadableAt)))
			resp.Header().Set("Retry-After", retryAfter)
			respondWithError(http.StatusServiceUnavailable, ctx.Err())
			return
		}
	}

	svcResponse := ServiceResponse{
		Token:       token.Token,
		Permissions: token.Permissions,
		ExpiresAt:   expiresAt.Format(time.RFC3339Nano),
		UsageCaps: UsageCaps{
			CanRunJob:         canRunJob(workflowBillingResponse),
			CanCreateArtifact: canCreateArtifact(workflowBillingResponse),
			BillingChecked:    workflowBillingResponse.IsBillingChecked,
		},
		Secrets:           secrets,
		Variables:         variables,
		SendIDToken:       sendIDToken,
		EnvironmentNodeID: environmentNodeID,
	}

	s.log.Debug(ctx, "pre-job response",
		kvp.String("gh.launch.prejob.token.permissions", fmt.Sprint(svcResponse.Permissions)),
		kvp.String("gh.launch.prejob.token.expires_at", svcResponse.ExpiresAt),
		kvp.Bool("gh.launch.prejob.can_run_job", svcResponse.UsageCaps.CanRunJob),
		kvp.Bool("gh.launch.prejob.can_create_artifact", svcResponse.UsageCaps.CanCreateArtifact),
		kvp.Int("gh.launch.prejob.environment_secret_count", len(envSecrets)),
		kvp.Int("gh.launch.prejob.integration_secret_count", len(integrationSecrets)),
		kvp.Int("gh.launch.prejob.total_secret_count", len(secrets)),
		kvp.Bool("gh.launch.prejob.send_id_token", sendIDToken),
		kvp.String("gh.launch.prejob.environment_node_id", environmentNodeID.String()),
	)

	resp.Header().Set("Content-Type", "application/json")
	resp.WriteHeader(http.StatusCreated)
	if err := json.NewEncoder(resp).Encode(&svcResponse); err != nil {
		err := errors.Wrap(err, "failed to encode pre-job token response")
		if svcerr.CallerShouldReportError(err) {
			s.log.Report(ctx, err)
		}
		respondWithError(http.StatusInternalServerError, err)
		return
	}
}

func (s *Servicer) makeTokenRequest(
	ctx context.Context, workflowID, jobID string, wb *workflowBuild, pjr *prejobRequest,
) (*token.GetTokenResponse, error) {
	tokenReq := s.buildTokenRequest(workflowID, jobID, wb, pjr)

	token, err := s.tokenTwirpService.GetToken(ctx, tokenReq)
	if err != nil {
		return nil, errors.Wrap(err, "Token RPC call to deployer failed")
	}

	return token, nil
}

// buildTokenRequest builds the request to fetch a token from the token service.
func (s *Servicer) buildTokenRequest(
	workflowID, jobID string, wb *workflowBuild, pjr *prejobRequest,
) (tokenReq *tk.GetTokenRequest) {
	workflowRunPermissions := make(map[string]string)

	// If the workflow is from codespaces, request the necessary permissions.
	if wb != nil && wb.isCodespaces() {
		workflowRunPermissions["codespaces_prebuild"] = string(tokens.WriteAccess)
	}

	return &tk.GetTokenRequest{
		WorkflowId:             workflowID,
		JobId:                  jobID,
		Permissions:            pjr.Permissions,
		WorkflowRunPermissions: workflowRunPermissions,
	}
}

func (s *Servicer) fetchEnvironmentSecrets(ctx context.Context, environment *ghtwirp.Environment, securityResponse *deploy.GetWorkflowSecurityDetailsResponse) (map[string]string, error) {
	// Retrieve Actions environment secrets if environment is specified and they're permitted.
	if environment == nil {
		return nil, nil
	}

	if !securityResponse.GetAreActionsEnvironmentSecretsAllowed() {
		s.log.Log(ctx, "Environment secrets not permitted")
		return nil, nil
	}

	envSecrets, err := GetEnvironmentSecrets(ctx, s.kredzClient, s.ghTwirpClient, s.secretDecryptor, environment.GlobalID, s.appRelayID, s.obs)
	if err != nil {
		return nil, errors.Wrap(err, "error retrieving environment secrets")
	}

	return envSecrets, nil
}

func (s *Servicer) fetchEnvironmentVariables(ctx context.Context, environment *ghtwirp.Environment, securityResponse *deploy.GetWorkflowSecurityDetailsResponse) (map[string]string, error) {
	// Retrieve Actions environment variables if environment is specified.
	if environment == nil {
		return nil, nil
	}

	if !securityResponse.GetAreActionsEnvironmentVariablesAllowed() {
		s.log.Log(ctx, "Environment variables not permitted")
		return nil, nil
	}

	envVariables, err := GetEnvironmentVariables(ctx, s.varzClient, s.ghTwirpClient, environment.GlobalID, s.appRelayID, s.obs)
	if err != nil {
		return nil, errors.Wrap(err, "error retrieving environment variables")
	}

	return envVariables, nil
}

type workflowBuild struct {
	data         *deployer.DataForPrejobtoken
	dynamicEvent *flowevents.DynamicEvent
}

func (wb *workflowBuild) isDynamic() bool {
	return wb != nil && wb.data.Event == flowevents.Dynamic && wb.dynamicEvent != nil
}

func (wb *workflowBuild) isCodespaces() bool {
	return wb.isDynamic() && wb.dynamicEvent.IntegrationName == constants.CodespacesIntegrationName
}

// fetchWorkflowBuild fetches the workflow build data for the given workflow ID.
// If the workflow is dynamic, it also fetches the dynamic event data. Callers
// should check the workflowBuild.isDynamic() method to determine if the workflow
// is dynamic and can use the dynamic event data.
func (s *Servicer) fetchWorkflowBuild(ctx context.Context, workflowID string, repoID types.GlobalID) (wb *workflowBuild, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	wfb, err := s.fetchWorkflowBuildData(ctx, workflowID)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error getting workflow build data"))
	}
	wb = &workflowBuild{data: wfb}

	if wb.data.Event != flowevents.Dynamic {
		// if workflow build is not dynamic, do not fetch the dynamic event data
		return wb, nil
	}

	wb.dynamicEvent, err = s.fetchWorkflowBuildEvent(ctx, wfb.WorkflowBuildDatabaseID, repoID)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error getting workflow build event data"))
	}

	return wb, nil
}

func (s *Servicer) fetchWorkflowBuildData(ctx context.Context, workflowID string) (*deployer.DataForPrejobtoken, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	wfb, ok, err := s.workflowbuildsRepo.GetDataForPrejobtoken(ctx, workflowID)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error retrieving workflow build information"))
	}

	if !ok {
		return nil, tracing.RecordError(span, terrors.NewNotFoundError(errors.New("workflow build not found")))
	}

	return wfb, nil
}

func (s *Servicer) fetchWorkflowBuildEvent(ctx context.Context, workflowBuildDatabaseID int64, repoID types.GlobalID) (ev *flowevents.DynamicEvent, err error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	eventPayload, err := s.workflowbuildsRepo.GetWorkflowBuildPayload(ctx, workflowBuildDatabaseID, repoID)
	if err != nil {
		return ev, tracing.RecordError(span, err)
	}

	err = json.Unmarshal(eventPayload, &ev)
	if err != nil {
		return ev, tracing.RecordError(span, errors.Wrap(err, "error decoding dynamic payload"))
	}

	return ev, nil
}

func (s *Servicer) fetchIntegrationSecrets(ctx context.Context, repoGlobalID types.GlobalID, wb *workflowBuild, pjr *prejobRequest, reqStartTime time.Time) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if !wb.isDynamic() {
		return nil, nil
	}

	_, repoDatabaseID, err := repoGlobalID.Decode()
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error decoding repo global id"))
	}

	var encSecrets map[string]string
	err = s.withReplicationRetry(ctx, freno.WorkflowRunsDBCluster, reqStartTime, "get_integration_job_secrets", func() error {
		encSecrets, err = s.ghTwirpClient.GetIntegrationJobSecrets(ctx, wb.dynamicEvent.IntegrationName, repoDatabaseID, wb.data.WorkflowRunID, pjr.BareJobName, pjr.EnvironmentName, pjr.IsHostedRunner, wb.dynamicEvent)
		return err
	})

	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error retrieving integration job secrets"))
	}

	if len(encSecrets) == 0 {
		return nil, nil
	}

	scope := getIntegrationEncryptionScope(repoDatabaseID)
	integrationSecrets, err := LocalDecryptSecrets(ctx, encSecrets, scope, s.secretDecryptor)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error decrypting integration job secrets"))
	}

	return integrationSecrets, nil
}

// withReplicationRetry attempts the f operation twice if the first attempt fails with a NotFound error and freno indicates replication may not have completed.
func (s *Servicer) withReplicationRetry(ctx context.Context, cluster string, maxWriteTime time.Time, operationName string, f func() error) error {
	retried := false
	status := ""
	errorType := ""
	defer func() {
		tags := statter.Tags{
			"operation_name":    operationName,
			"operation_retried": strconv.FormatBool(retried),
			"operation_status":  status,
		}
		if errorType != "" {
			tags["error_type"] = errorType
		}
		s.obs.Counter(ctx, "freno_lag_retrier", tags, 1)
	}()

	// First attempt
	fErr := f()
	if fErr == nil {
		status = "success"
		return nil
	}

	status = "error"
	if terrors.IsNotFoundError(fErr) {
		errorType = "not_found"
	} else {
		errorType = "other"
		return fErr
	}

	// Check freno lag
	s.obs.Log(ctx, "not found error response, checking freno", kvp.String("gh.freno.cluster.name", cluster))
	frenoLag, err := s.frenoClient.Check(ctx, cluster)
	if err != nil {
		s.obs.Report(ctx, errors.Wrap(err, "attempting to query freno lag"))
		return fErr
	}

	completeTime := maxWriteTime.Add(frenoLag.ReplicationLag)
	wait := time.Until(completeTime)
	if wait <= 0 {
		s.obs.Debug(ctx, "replication should already be complete, skipping retry",
			kvp.String("gh.freno.cluster.name", cluster),
			kvp.Time("gh.launch.prejob.max_write_time", maxWriteTime),
			kvp.Time("gh.launch.prejob.replication_complete_time", completeTime))

		return fErr
	}

	if wait > maxReplicationWait {
		s.log.Report(ctx, errors.New("replication lag too high to wait for"),
			kvp.String("gh.freno.cluster.name", cluster),
			kvp.Time("gh.launch.prejob.max_write_time", maxWriteTime),
			kvp.Time("gh.launch.prejob.replication_complete_time", completeTime),
			kvp.Duration("gh.freno.lag_seconds", frenoLag.ReplicationLag),
			kvp.Duration("gh.launch.prejob.wait_sec", wait),
			kvp.Duration("gh.launch.prejob.max_wait_time_sec", maxReplicationWait))

		wait = maxReplicationWait
	}

	// Wait before retrying
	select {
	case <-time.After(wait):
	case <-ctx.Done():
		s.log.Log(ctx, "timed out waiting for replication to complete", kvp.Duration("gh.launch.prejob.wait_sec", wait))
		return fErr
	}

	s.obs.Distribution(ctx, "freno_lag_retrier.wait_ms", statter.Tags{
		"operation_name": operationName,
	}, float64(wait.Milliseconds()))

	s.obs.Debug(ctx, "done waiting for replication to complete, retrying operation",
		kvp.String("gh.freno.cluster.name", cluster),
		kvp.Duration("gh.freno.lag_seconds", frenoLag.ReplicationLag),
		kvp.Duration("gh.launch.prejob.wait_sec", wait))

	// Second and final attempt
	retried = true
	errorType = ""
	fErr = f()
	if fErr == nil {
		status = "success"
		return nil
	}

	status = "error"
	if terrors.IsNotFoundError(fErr) {
		errorType = "not_found"
	} else {
		errorType = "other"
	}
	return fErr
}

// Enables us to monitor spikes in billing related job failures.
func (s *Servicer) recordBillingStat(ctx context.Context, workflowBillingResponse *deploy.WorkflowBillingDetailsResponse) {
	tags := statter.Tags{
		"usage_allowed":   strconv.FormatBool(workflowBillingResponse.IsUsageAllowed),
		"storage_allowed": strconv.FormatBool(workflowBillingResponse.IsStorageAllowed),
		"spammy":          strconv.FormatBool(workflowBillingResponse.IsOwnerSpammy),
	}
	s.stats.Counter(ctx, "receiver.pre_job_billing", tags, 1)
}

func (s *Servicer) recordSecurityStat(ctx context.Context, securityResponse *deploy.GetWorkflowSecurityDetailsResponse) {
	tags := statter.Tags{
		"actions_secrets_allowed":     strconv.FormatBool(securityResponse.AreActionsSecretsAllowed),
		"actions_env_secrets_allowed": strconv.FormatBool(securityResponse.AreActionsEnvironmentSecretsAllowed),
		"id_token_generation_allowed": strconv.FormatBool(securityResponse.IsIDTokenGenerationAllowed),
	}
	s.stats.Counter(ctx, "receiver.pre_job_security", tags, 1)
}

func (s *Servicer) emitResponseDelay(ctx context.Context, delay time.Duration) {
	if delay < 0 {
		delay = 0
	}
	s.obs.Distribution(ctx, "response_delay_ms", statter.Tags{"endpoint": "pre_job_tokens"}, float64(delay.Milliseconds()))
}

func canRunJob(workflowBillingResponse *deploy.WorkflowBillingDetailsResponse) bool {
	if workflowBillingResponse.GetIsOwnerSpammy() {
		return false
	}

	return workflowBillingResponse.GetIsUsageAllowed()
}

func canCreateArtifact(workflowBillingResponse *deploy.WorkflowBillingDetailsResponse) bool {
	if workflowBillingResponse.GetIsOwnerSpammy() {
		return false
	}

	return workflowBillingResponse.GetIsStorageAllowed()
}

func getIntegrationEncryptionScope(repoDatabaseID int64) string {
	// Using a repository database ID because we're migrating away from global IDs soon. If we want to change the scope
	// format, perhaps to include the object type as well, we may want to update GetIntegrationJobSecretsResponse to
	// include the scope used for encryption. See Api::Internal::Twirp::Actions::GetIntegrationJobSecrets#scope in dotcom.
	return strconv.FormatInt(repoDatabaseID, 10)
}

func (s *Servicer) fetchEnvironment(ctx context.Context, environmentName string, repoGlobalID types.GlobalID, reqStartTime time.Time) (*ghtwirp.Environment, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if environmentName == "" {
		return nil, nil
	}

	var err error
	var env *ghtwirp.Environment
	err = s.withReplicationRetry(ctx, freno.EnvironmentsDBCluster, reqStartTime, "resolve_environment", func() error {
		env, err = s.ghTwirpClient.ResolveEnvironment(ctx, environmentName, repoGlobalID)
		return err
	})

	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "error retrieving environment information"))
	}

	return env, nil
}

func (s *Servicer) ServiceContext(r *http.Request) {
	appcontext.SetupServiceContext(r)
}

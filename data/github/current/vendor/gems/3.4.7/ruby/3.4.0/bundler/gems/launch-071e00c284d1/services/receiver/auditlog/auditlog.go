package auditlog

import (
	"context"
	"net/http"
	"strconv"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/wrappers"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	oteltrace "go.opentelemetry.io/otel/trace"

	"github.com/github/launch/pkg/mu"
	"github.com/github/launch/pkg/mu/muhttp/mw"

	"github.com/github/launch/auth"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/measurehttp"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/thresholds"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/utils/appcontext"
)

// Service handles requests in the /actions/runner namespace
type Service struct {
	cfg            *Config
	obs            *observability.Observability
	hydro          events.Hydro
	db             deployer.AzpResourcesLoader
	vaultName      string
	keyVaultClient azp.KeyVaultClient
	verifier       auth.Verifier
	ghTwirpClient  ghtwirp.Client
}

type Config struct {
	IsDevelopment               bool
	IsEnterprise                bool
	IsMultiTenant               bool
	ActionsAuthHmacKeyPrimary   string
	ActionsAuthHmacKeySecondary string
}

// NewService returns a Service
func NewService(
	cfg *Config,
	obs *observability.Observability,
	hydro events.Hydro,
	db deployer.AzpResourcesLoader,
	vaultName string,
	keyVaultClient azp.KeyVaultClient,
	verifier auth.Verifier,
	ghTwirpClient ghtwirp.Client,
) *Service {
	return &Service{
		cfg:            cfg,
		obs:            obs,
		hydro:          hydro,
		db:             db,
		vaultName:      vaultName,
		keyVaultClient: keyVaultClient,
		verifier:       verifier,
		ghTwirpClient:  ghTwirpClient,
	}
}

var _ mu.Servicer = (*Service)(nil)

const (
	runnerUpdatedRoute       = `/actions/runner/updated`
	runnerOnlineRoute        = `/actions/runner/online`
	runnerOfflineRoute       = `/actions/runner/offline`
	workflowJobPreparedRoute = `/actions/workflow_job/prepared`
)

const (
	Repository   = "Repository"
	Organization = "Organization"
	Enterprise   = "Enterprise"
)

// Routes that the service exposes
func (s *Service) Routes() []mu.Route {
	return []mu.Route{
		mu.Post(runnerUpdatedRoute, s.HandleRunnerUpdated()),
		mu.Post(workflowJobPreparedRoute, s.HandleWorkflowJobPrepared()),
		mu.Post(runnerOnlineRoute, s.HandleRunnerStateChange("online")),
		mu.Post(runnerOfflineRoute, s.HandleRunnerStateChange("offline")),
	}
}

// ServiceContext applied to every request
func (s *Service) ServiceContext(req *http.Request) {
	appcontext.SetupServiceContext(req)
}

func tags(code int) statter.Tags {
	tags := statter.Tags{
		"status_code": strconv.Itoa(code),
	}
	return tags
}

func (s *Service) respond(resp http.ResponseWriter, route string, span oteltrace.Span) func(ctx context.Context, code int, err error) { //nolint:staticcheck
	return func(ctx context.Context, code int, err error) {
		tags := tags(code)
		s.obs.Counter(ctx, route, tags, 1)

		if err != nil {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.launch.auditlog_result", "error"), kvp.Err(err))
			s.obs.Error(ctx, err.Error(), kvp.Int("http.response.status_code", code))
			span.RecordError(err)
			http.Error(resp, http.StatusText(code), code)
			return
		}
		resp.WriteHeader(code)
	}
}

func (s *Service) withThreshold(f http.HandlerFunc, errorName string) http.HandlerFunc {
	return func(resp http.ResponseWriter, req *http.Request) {
		ctx, span := tracing.Start(req.Context())
		defer span.End()

		if err := measurehttp.SetThreshold(req.Context(), thresholds.HTTPAuditLogLatency); err != nil {
			respondWithError := s.respond(resp, errorName, span)
			respondWithError(ctx, http.StatusInternalServerError, errors.Wrap(err, "couldn't find measurement struct in context"))
			return
		}

		f(resp, req)
	}
}

type auditLogDefaults struct {
	Action        string `json:"action"`
	DocumentID    string `json:"_document_id"`
	CategoryType  string `json:"category_type"`
	OperationType string `json:"operation_type"`
	CreatedAt     int64  `json:"created_at"`
	Timestamp     int64  `json:"@timestamp"`
}

func stringValue(in string) *wrappers.StringValue {
	return &wrappers.StringValue{Value: in}
}

func getDocumentID(ctx context.Context) string {
	if reqID := mw.GetGitHubRequestID(ctx); reqID != "" {
		return reqID
	}
	return uuid.New().String()
}

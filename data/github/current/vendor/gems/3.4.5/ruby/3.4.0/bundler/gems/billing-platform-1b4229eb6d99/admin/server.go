package admin

import (
	"embed"
	"fmt"
	"html/template"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/okta"
	"github.com/github/feature-management-client-go/vexi"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	"github.com/github/go-stats"
	"github.com/gorilla/csrf"
	"github.com/pkg/errors"
)

//go:embed static/*
var staticFiles embed.FS

//go:embed templates/query.html
var queryTemplate string

type AdminServer struct {
	Logger         log.Logger
	Statter        stats.Client
	ErrorReporter  *exceptions.Reporter
	Flagger        *vexi.Client
	ReadOnlyDBCon  interfaces.CosmosConnection
	PK             string
	OktaHMACSecret string
	Environment    string
}

func (s *AdminServer) renderQueryTemplate(w http.ResponseWriter, r *http.Request, results QueryResults, isQueryError bool) {
	tmpl := template.New(queryTemplate)
	_, err := tmpl.Parse(queryTemplate)
	if err != nil {
		s.Logger.WithError(err).Error("failed to parse template")
	}

	stamps, err := LoadStamps(s.Environment)
	if err != nil {
		s.Logger.WithError(err).Error("failed to load stamps")
	}

	// sort the stamps, moving the current stamp to the top. This is a bit of a hack to avoid
	// setting the default selected value in HTML which isn't very trivial to do in Go's template language.
	if len(stamps.Stamps) > 1 {
		for i, stamp := range stamps.Stamps {
			if stamp.Stamp == s.Environment {
				stamps.Stamps[0], stamps.Stamps[i] = stamps.Stamps[i], stamps.Stamps[0]
				break
			}
		}
	}

	templateData := map[string]interface{}{
		"query":          results,
		"isQueryError":   isQueryError,
		"stamp":          s.Environment,
		"stamps":         stamps.Stamps,
		csrf.TemplateTag: csrf.TemplateField(r),
	}

	if results.PartitionKey != "" && results.QueryString != "" {
		templateData["shareableURL"] = fmt.Sprintf("?pk=%s&query=%s", url.QueryEscape(results.PartitionKey), url.QueryEscape(results.QueryString))
	}

	err = tmpl.Execute(w, templateData)

	if err != nil {
		s.Logger.WithError(err).Error("failed to execute template")
	}
}

func NewAdminServer(logger log.Logger, statter stats.Client, errorReporter *exceptions.Reporter, flagger *vexi.Client, readOnlyDBCon interfaces.CosmosConnection, pk string, oktaHMACString string, environment string) *AdminServer {
	return &AdminServer{
		Logger:         logger,
		Statter:        statter,
		ErrorReporter:  errorReporter,
		Flagger:        flagger,
		ReadOnlyDBCon:  readOnlyDBCon,
		PK:             pk,
		OktaHMACSecret: oktaHMACString,
		Environment:    environment,
	}
}

func (s *AdminServer) RootHandler(w http.ResponseWriter, r *http.Request) {
	s.Logger.Info("Request to /")

	queryString := r.URL.Query().Get("query")
	partitionKey := r.URL.Query().Get("pk")

	if queryString != "" && partitionKey != "" {
		decodedQueryString, err := url.QueryUnescape(queryString)
		if err != nil {
			s.Logger.WithError(err).Error("failed to decode query string")
			http.Error(w, "failed to decode query string", http.StatusBadRequest)
			return
		}
		queryString = decodedQueryString

		decodedPartitionKey, err := url.QueryUnescape(partitionKey)
		if err != nil {
			s.Logger.WithError(err).Error("failed to decode partition key")
			http.Error(w, "failed to decode partition key", http.StatusBadRequest)
			return
		}
		partitionKey = decodedPartitionKey

		s.renderQueryTemplate(w, r, QueryResults{QueryString: queryString, PartitionKey: partitionKey}, false)
	} else {
		s.renderQueryTemplate(w, r, QueryResults{QueryString: "select * from c"}, false)
	}
}

func (s *AdminServer) QueryHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		s.Logger.Info("Request to /query")
	default:
		s.Logger.Error("Method not allowed to /query")
		http.Redirect(w, r, "/", http.StatusTemporaryRedirect)

		return
	}

	username, bool := okta.GetUsername(r.Context())
	if !bool {
		s.Logger.Error("failed to get username")
		http.Error(w, "failed to get username", http.StatusInternalServerError)

		return
	}

	queryString := r.FormValue("query")
	if queryString == "" {
		s.Logger.Error("query string is empty")
		http.Error(w, "query string is empty", http.StatusBadRequest)
		return
	}

	partitionKey := r.FormValue("partitionKey")
	if partitionKey == "" {
		s.Logger.Error("partition key is empty")
		http.Error(w, "partition key is empty", http.StatusBadRequest)
		return
	}

	s.Logger.Info("Performing query from admin tool", kvp.String("query", queryString), kvp.String("partitionKey", partitionKey), kvp.String("username", username))
	isQueryError := false
	items, elapsedTime, totalResultsCount, requestCharge, totalRetrievedDocumentSize, totalOutputDocumentSize, err := s.getQueryItems(r.Context(), queryString, partitionKey)
	if err != nil {
		s.Logger.WithError(err).Error("failed to query items")
		items = "Invalid query"
		isQueryError = true

	}

	if items == "" {
		items = "No results"
	}

	s.renderQueryTemplate(
		w,
		r,
		QueryResults{
			Results:                  items,
			QueryString:              queryString,
			PartitionKey:             partitionKey,
			QueryTime:                elapsedTime,
			ResultsCount:             totalResultsCount,
			RequestCharge:            requestCharge,
			RetrievedDocumentSizeKiB: totalRetrievedDocumentSize,
			OutputDocumentSizeKiB:    totalOutputDocumentSize,
		},
		isQueryError,
	)
}

func (s *AdminServer) PingHandler(w http.ResponseWriter, r *http.Request) {
	s.Logger.Info("Request to /_ping")
	fmt.Fprint(w, "pong")
}

func (s *AdminServer) BoomHandler(writer http.ResponseWriter, request *http.Request) {
	s.Logger.Info("boom")
	err := s.ErrorReporter.Report(request.Context(), errors.New("this is an error from the admin tool"), map[string]string{"location": "/_boom"})
	if err != nil {
		s.Logger.WithError(err).Error("boom error")
	}
	panic("boom!")
}

func (s *AdminServer) FeatureFlagHandler(w http.ResponseWriter, r *http.Request) {
	s.Logger.Info("Request to /_feature_flag")
	start := time.Now()
	flag := s.Flagger.IsEnabledWithDefaultValue(r.Context(), "billing_admin_vexi_test", false, models.CustomerVexiActor("1061737"))
	s.Statter.Timing("test-vexi-flag-check-latency", stats.Tags{"enabled": strconv.FormatBool(flag)}, time.Since(start))

	if flag {
		fmt.Fprint(w, "feature flag: billing_admin_vexi_test is enabled")
		s.Logger.Info("feature flag: billing_admin_vexi_test is enabled")
	} else {
		fmt.Fprint(w, "feature flag: billing_admin_vexi_test is NOT enabled")
		s.Logger.Info("feature flag: billing_admin_vexi_test is NOT enabled")
	}
}

func (s *AdminServer) StaticFileHandler(w http.ResponseWriter, r *http.Request) {
	s.Logger.Info(fmt.Sprintf("Request to static file %v", r.URL.Path))
	fileHandler := http.FileServer(http.FS(staticFiles))
	fileHandler.ServeHTTP(w, r)
}

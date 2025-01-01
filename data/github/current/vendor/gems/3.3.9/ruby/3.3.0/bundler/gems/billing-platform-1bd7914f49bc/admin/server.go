package admin

import (
	"embed"
	"fmt"
	"html/template"
	"net/http"

	"github.com/github/billing-platform/lib/interfaces"
	"github.com/github/billing-platform/lib/okta"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	exceptions "github.com/github/go-exceptions"
	"github.com/gorilla/csrf"
	"github.com/pkg/errors"
)

//go:embed static/*
var staticFiles embed.FS

//go:embed templates/query.html
var queryTemplate string

type AdminServer struct {
	Logger         log.Logger
	ErrorReporter  *exceptions.Reporter
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

	templateData := map[string]interface{}{
		"query":          results,
		"isQueryError":   isQueryError,
		"stamp":          s.Environment,
		csrf.TemplateTag: csrf.TemplateField(r),
	}

	err = tmpl.Execute(w, templateData)

	if err != nil {
		s.Logger.WithError(err).Error("failed to execute template")
	}
}

func NewAdminServer(logger log.Logger, errorReporter *exceptions.Reporter, readOnlyDBCon interfaces.CosmosConnection, pk string, oktaHMACString string, environment string) *AdminServer {
	return &AdminServer{
		Logger:         logger,
		ErrorReporter:  errorReporter,
		ReadOnlyDBCon:  readOnlyDBCon,
		PK:             pk,
		OktaHMACSecret: oktaHMACString,
		Environment:    environment,
	}
}

func (s *AdminServer) RootHandler(w http.ResponseWriter, r *http.Request) {
	s.Logger.Info("Request to /")

	s.renderQueryTemplate(w, r, QueryResults{QueryString: "select * from c"}, false)
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
	items, elapsedTime, totalResultsCount, requestCharge, err := s.getQueryItems(r.Context(), queryString, partitionKey)
	if err != nil {
		s.Logger.WithError(err).Error("failed to query items")
		items = "Invalid query"
		isQueryError = true

	}

	if items == "" {
		items = "No results"
	}

	s.renderQueryTemplate(w, r, QueryResults{Results: items, QueryString: queryString, PartitionKey: partitionKey, QueryTime: elapsedTime, ResultsCount: totalResultsCount, RequestCharge: requestCharge}, isQueryError)
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

func (s *AdminServer) StaticFileHandler(w http.ResponseWriter, r *http.Request) {
	s.Logger.Info(fmt.Sprintf("Request to static file %v", r.URL.Path))
	fileHandler := http.FileServer(http.FS(staticFiles))
	fileHandler.ServeHTTP(w, r)
}

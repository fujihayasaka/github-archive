// Package root provides the service that powers code scanning on GitHub
package root

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/pprof"
	"strings"

	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/delivery"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/mysql/tool"

	"github.com/github/turboscan/ts/enabled_status"

	"github.com/github/turboscan/ts/limits"

	"github.com/github/turboscan/ts/alertlinks"
	"github.com/github/turboscan/ts/mysql/alertlink"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/pr_alerts"
	"github.com/github/turboscan/ts/mysql/repository"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"

	"github.com/github/turboscan/ts/archivalstore"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-http/v2/middleware/hmac"
	"github.com/github/go-http/v2/middleware/recovery"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-staffbar"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twauth "github.com/github/go-twirp/v2/server/hooks/auth"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"

	"github.com/jinzhu/gorm"
	"github.com/justinas/alice"
	"github.com/pkg/errors"
	"github.com/spf13/cobra"

	"github.com/twitchtv/twirp"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/chatops"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/errutil"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/hydro/publishers"
	tstwirp "github.com/github/turboscan/ts/twirp"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/managed_analyses"
	"github.com/github/turboscan/ts/twirp/suggested_fixes"
)

const svcName = "turboscansvc"

var TurboscanSvcCmd = &cobra.Command{
	Use:   "turboscansvc",
	Short: "Runs the service that powers the Code Scanning service in GitHub",
	Long:  "Runs the service that powers the Code Scanning service in GitHub.",
	RunE: func(cmd *cobra.Command, args []string) error {
		return app.RunServiceFunc(svcName, serviceFunc)
	},
}

func serviceFunc(ctx context.Context, cfg *config.Config) (app.Server, app.CleanupFunc, error) {
	logger, statter := appctx.Logger(ctx), appctx.Stats(ctx)

	var cleanup app.Cleaner

	// Intentionally use a replica, but only for endpoints where the information is not persisted in other services
	// (like annotations, for example) and a refresh from the user will show the correct information when
	// there is replication lag.
	db, closeDB, err := app.NewDBWithReplica(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeDB)

	hooks := twirp.ChainHooks(
		twhooks.DefaultHooks(),
		twlog.DefaultHooks(logger),
		twstats.DefaultHooks(statter),
		failbotErrorHook(),
	)

	hooks, err = setUpQueryReporterHook(hooks, db)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	// Don't validate the HMAC in development
	if cfg.Environment != "development" {
		hooks = twirp.ChainHooks(
			hooks,
			twauth.VerifyRequestHMACHooks(cfg.ValidHMACs()...),
		)
	}

	es, err := app.NewES(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	kc, err := cfg.NewKafkaConfig(logger, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	publisher, err := publishers.New(*kc, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(publisher.Close)

	alertService, err := app.NewAlertService(db)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	insightHandler := publishers.NewInsightsHydroAlertHandler(publisher, alertService)

	sarifStore, closeSarifStore, err := app.NewSarifStore(ctx, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}
	cleanup.Append(closeSarifStore)

	jobs, err := aqueduct.NewClient(cfg, logger, statter, nil)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	archivalStore, err := archivalstore.NewArchivalStoreFromConfig(sarifStore, cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	alertLinkService := alertlink.NewService(db)

	repoService := repository.NewService(db)

	archiveService := archiver.NewService(db, archivalStore, archiver.WithConcurrency(cfg.ArchiverConcurrency))

	maDataService := managedanalysis.NewService(db, publisher)

	enabledStatusService := enabled_status.NewEnabledStatusService(db, alertService, repoService, maDataService, publisher, true)

	repoAPI, err := cfg.NewRepositoryAPI(logger, statter)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	maService, err := app.NewManagedAnalysisService(ctx, cfg, repoAPI, repoService, enabledStatusService, maDataService, publisher)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	limitsSelector := limits.NewLimitSelector(cfg.Limits(), cfg.DisableSarifHardLimit)

	sfDataService := sfdb.NewService(db)

	sfService, err := app.NewSuggestedFixesService(ctx, cfg, sfDataService, alertService, archiveService, limitsSelector, publisher)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	rr := tstwirp.NewResultsResolver(
		alertService,
		alertlinks.NewService(alertLinkService, publisher, es),
		pr_alerts.NewService(db),
		delivery.NewService(db),
		timeline.NewService(db),
		tool.NewService(db, limitsSelector),
		repoService,
		sfDataService,
		analysismessage.NewService(db),
		archiveService,
		sarifStore,
		archivalStore,
		es,
		publishers.NewHydroAlertHandler(publisher),
		insightHandler,
		jobs,
		enabledStatusService,
		cfg.IsEnterpriseEnv(),
	)
	ma := managed_analyses.New(maService, cfg.JavaBuildlessDisabled, cfg.CSharpBuildlessDisabled)
	sf := suggested_fixes.New(sfService, sarifStore, jobs, es)

	// set up a chatops handler
	chatopsHandler, err := chatops.NewChatopsHandler(cfg)
	if err != nil {
		return nil, cleanup.Clean, err
	}

	// set up a panic handler
	rec := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			p := map[string]string{
				"method": req.Method,
				"url":    req.URL.String(),
			}

			appctx.Report(req.Context(), err, p)
			return nil
		},
		// NOTE(arslan): some handlers might write to ResponseWriter before us.
		// For example the Twirp handler does it in case of a panic. In that
		// case we might see a log in the form of: `http: superfluous
		// response.WriteHeader call`. This means that a second `WriteHeader()`
		// call was made. It's logged to indicate a bug in a code base. However
		// this will happen very rare, such as a panic in a Twirp, so It's ok
		// to see that in that case, but it's worth knowing the cause. To fix
		// it we have to prevent writing it here.
		Response: func(err error, w http.ResponseWriter, r *http.Request) {
			http.Error(w, "unable to process the request", http.StatusInternalServerError)
		},
	}

	// start registering our handlers
	mux := http.NewServeMux()
	mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "OK")
	})
	mux.HandleFunc("/_report", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "Invalid Method", http.StatusBadRequest)
			return
		}

		var payload map[string]string
		if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
			http.Error(w, "Invalid JSON Body", http.StatusBadRequest)
			return
		}

		appctx.Report(r.Context(), errors.New(payload["err"]), payload)
		_, _ = fmt.Fprint(w, "reported!")
	})

	mux.HandleFunc("/debug/pprof/", pprof.Index)
	mux.HandleFunc("/debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("/debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("/debug/pprof/trace", pprof.Trace)

	mux.Handle("/_chatops", chatopsHandler)
	mux.Handle("/", app.Handler(rr, rr, ma, sf, hooks))

	wrappedMux := alice.New(
		rec.Handler,
		hmac.Handler,
		requestid.Handler,
		(&tenant.Tenant{}).Handler,
		staffbar.Handler,
		userAgentExtractor,
		app.SpecialTimeoutHandler.Handler,
	).Then(mux)
	addr := fmt.Sprintf(":%d", cfg.TurboscanPort)
	serverCtx := appctx.WithLogger(ctx, logger.WithFields(kvp.String("gh.turboscan.service_type", "twirp")))
	server := app.NewHTTPServer(serverCtx, addr, wrappedMux)

	return server, cleanup.Clean, nil
}

type httpHeaderContext int

const userAgentKey httpHeaderContext = iota

func userAgentExtractor(base http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()
		userAgent := r.Header.Get("User-Agent")
		r = r.WithContext(context.WithValue(ctx, userAgentKey, userAgent))

		base.ServeHTTP(w, r)
	})
}

// failbotErrorHook reports an errors with the given reporter.
func failbotErrorHook() *twirp.ServerHooks {
	return &twirp.ServerHooks{
		Error: func(ctx context.Context, twerr twirp.Error) context.Context {
			// prepare and send metrics
			tags := stats.Tags{
				"gh.turboscan.twirp_error_code": string(twerr.Code()),
			}
			if m, ok := twirp.MethodName(ctx); ok {
				tags["rpc.method"] = m
			}
			serviceName := ""
			if m, ok := twirp.PackageName(ctx); ok {
				serviceName += m + "."
			}
			if m, ok := twirp.ServiceName(ctx); ok {
				serviceName += m
			}
			if m, ok := twirp.StatusCode(ctx); ok {
				tags["http.status_code"] = m
			}
			if serviceName != "" {
				tags["rpc.service"] = serviceName
			}
			appctx.Stats(ctx).Counter("server.unhandled.error", tags, 1)

			// Benign errors are not logged to sentry
			if errutil.IsBenign(twerr) {
				return ctx
			}

			// Errors from manual curl requests are ignored.
			if userAgent, ok := ctx.Value(userAgentKey).(string); ok && strings.HasPrefix(userAgent, "curl/") {
				appctx.Stats(ctx).Counter("server.ignored.error", tags, 1)
				return ctx
			}

			// prepare exception (sentry) report
			requestID := requestid.GetGitHubRequestID(ctx)
			payload := map[string]string{
				"gh.request.id": requestID,
			}
			for k, v := range tags {
				// Use # prefix to make the tags searchable in Sentry
				payload[fmt.Sprintf("#%s", k)] = v
			}

			// twirp wraps errors for pkg/errors interoperability whenever we
			// use "twirp.InternalErrorWith()". This allows us to return the
			// underlying error, which is of type `github.com/pkg/errors` and
			// contains a backtrace
			err := errutil.LastCause(twerr)

			sensitivePayload := map[string]string{}

			queryError := &gormext.QueryError{}
			if errors.As(err, &queryError) {
				payload["db.statement"] = queryError.SQL
				marshaledSQLVars, err := json.Marshal(queryError.SQLVars)
				if err != nil {
					sensitivePayload["gh.turboscan.db.statement_variables"] = "Error marshaling SQL vars: " + err.Error()
				} else {
					sensitivePayload["gh.turboscan.db.statement_variables"] = string(marshaledSQLVars)
				}
			}

			// note that we redact Gorm errors, however passing `err` allows us
			// to store the backtrace, so don't change `err` here
			appctx.ReportSensitive(ctx, err, payload, sensitivePayload)

			return ctx
		},
	}
}

func setUpQueryReporterHook(hooks *twirp.ServerHooks, db *gorm.DB) (*twirp.ServerHooks, error) {
	logger, ok := db.Get("staffbarLogger")
	if !ok {
		return nil, errors.New("staffbarLogger not set on gorm DB")
	}
	wrappedLogger, ok := logger.(staffbar.GormLogger)
	if !ok {
		return nil, errors.New("staffbarLogger not set on gorm DB")
	}

	return twirp.ChainHooks(hooks, &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			db.SetLogger(staffbar.NewGormLogger(ctx, wrappedLogger))
			return ctx, nil
		},

		ResponseSent: func(ctx context.Context) {
			db.SetLogger(wrappedLogger)
		},

		Error: func(ctx context.Context, err twirp.Error) context.Context {
			db.SetLogger(wrappedLogger)
			return ctx
		},
	}), nil
}

package main

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/signal"
	"runtime"
	"runtime/debug"
	"syscall"

	"github.com/github/go-http/middleware/recovery"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/admin"
	"github.com/github/blackbird-mw/internal/deltaingest"
	"github.com/github/blackbird-mw/internal/env"
	mwhttp "github.com/github/blackbird-mw/internal/http"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kube"
	pb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	"github.com/github/blackbird-mw/internal/publish/backfill"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/utils"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cfg := env.New(ctx)
	defer cfg.Close()
	defer utils.PanicLogger(ctx)

	logging.Info(ctx, fmt.Sprintf("%s starting up", cfg.App()),
		kvp.String("cfg", fmt.Sprintf("%+v", cfg)),
		kvp.Int("go_max_procs", runtime.GOMAXPROCS(-1)),
	)

	store := cfg.Store()
	searchClusters := cfg.SearchClusters()
	cacheClusters := cfg.CacheClusters()
	indexerClusters := cfg.IndexerClusters()

	snapshotProducer := cfg.SnapshotProducer()
	defer snapshotProducer.Close()

	repoPublisher := cfg.RepoPublisher()
	defer repoPublisher.Close()

	gitClient := cfg.GitClient()

	pager := cfg.PagerCache()

	sharedKafkaAdmin := cfg.SharedKafkaAdminClient()
	defer sharedKafkaAdmin.Close()

	sharedKafkaClient := cfg.SharedAutoCommittingKafkaClient()
	defer sharedKafkaClient.Close()

	blackbirdKafkaAdmin := cfg.BlackbirdKafkaAdminClient()
	defer blackbirdKafkaAdmin.Close()

	tc := cfg.TopicConfig()

	detector := deltaingest.NewIngestModeDetector(store, sharedKafkaAdmin, blackbirdKafkaAdmin, snapshotProducer, int(tc.Backfill.Partitions), cfg.GetStamp())
	detector.Run(ctx)

	tsReader := kafka.NewDelayedTimestampReader(func() kafka.MessageReader {
		msgReader, err := kafka.NewSaramaMessageReader(cfg.SharedAutoCommittingKafkaClient())
		if err != nil {
			panic(fmt.Errorf("failed to create kafka msg reader: %w", err))
		}
		return msgReader
	}, routing.IncrementalSourceTopic)
	tsReader.Run(ctx)

	adminAPI := admin.NewService(
		searchClusters,
		cacheClusters,
		indexerClusters,
		store,
		pager,
		gitClient,
		cfg.GitHubClient(),
		cfg.ChatClient(),
		cfg.BlackbirdKafkaAdminProvider(),
		sharedKafkaClient,
		tc,
		backfill.NewPublisher(
			store,
			snapshotProducer,
			searchClusters,
			cacheClusters,
			cfg.ChatClient(),
			uint32(tc.Document.Partitions),
			uint32(tc.Backfill.Partitions),
		),
		repoPublisher,
		snapshotProducer,
		cfg.QuotaRateEstimator(ctx),
		cfg.AssignmentsReader(),
		cfg.SitesAPIClient(),
		cfg.GetStamp(),
		tsReader,
		kafka.NewConsumerGroupManager(sharedKafkaAdmin),
	)
	adminServer := pb.NewAdminAPIServer(adminAPI, cfg.AdminServiceHooks())
	chatopsServer := admin.NewChatopsService(cfg, adminAPI, cfg.ChatClient())
	handler := buildHTTPMux(ctx, cfg, adminServer, chatopsServer)
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", cfg.GetHTTPPort()),
		Handler: handler,
	}

	// Wait on OS signals and allow graceful shutdown.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		defer utils.PanicLogger(ctx)
		defer close(stop)
		defer cancel()

		// Received stop signal (SIGINT/SIGTERM)
		<-stop
		logging.Info(ctx, "received shutdown signal, exiting")
		err := server.Shutdown(ctx) // Do this last so that k8s probes stay alive
		if err != nil {
			logging.Error(ctx, "server.Shutdown failed", kvp.Err(err))
		}
	}()

	logging.Info(ctx, "starting admin web server", kvp.Int("port", cfg.GetHTTPPort()))
	if err := server.ListenAndServe(); err != nil {
		if err == http.ErrServerClosed {
			logging.Info(ctx, "admin server has shutdown", kvp.Err(err))
		} else {
			logging.Error(ctx, "admin server exited with error", kvp.Err(err))
		}
	}

	logging.Info(ctx, "exiting...")
}

func buildHTTPMux(ctx context.Context, cfg env.Config, twirpServer pb.TwirpServer, chatopsServer *admin.ChatopsServer) http.Handler {
	mux := chi.NewRouter()
	mux.Use(requestid.Handler)
	mux.Mount("/debug", middleware.Profiler())
	mux.HandleFunc("/ready", kube.Ready(cfg))

	rec := recovery.Recovery{
		Report: func(err error, req *http.Request) error {
			logging.Error(req.Context(), "unhandled panic occurred", kvp.Err(err),
				kvp.String("path", req.URL.Path),
				kvp.String("stack", string(debug.Stack())))
			statting.Counter(req.Context(), "panic_count", 1, stats.Tags{"path": req.URL.Path})

			return twirp.InternalError("internal server error")
		},
	}

	if cfg.IsChatopsEnabled() {
		chatopsServer.RegisterCommands(mux)
	} else {
		logging.Info(ctx, "chatops disabled, set BLACKBIRD_MW_CHATOPS_AUTH_PUBLIC_KEY to enable")
	}

	// TODO: Protect stamp admin services with their own hmac
	if cfg.AdminUIEnabled() {
		// Proxy requests to the admin service in the each stamp
		stampProxies := map[string]*httputil.ReverseProxy{}
		for _, stamp := range routing.ProximaStamps {
			host := fmt.Sprintf("blackbird-admin.service.%s.github.net", string(stamp))
			stampProxies[string(stamp)] = &httputil.ReverseProxy{
				Rewrite: func(pr *httputil.ProxyRequest) {
					pr.SetURL(&url.URL{Scheme: "https", Host: host})
				},
			}
		}

		proxy := reverseProxy{
			stamps: stampProxies,
		}

		// NOTE: Anything using this handler can ONLY be accessed from
		// blackbird.githubapp.com in production.
		//
		// An Okta HMAC is required and verified to access the API.
		oktaAuthHandler := cfg.OktaAuthHandler()

		// The twirp admin service
		mux.Mount(twirpServer.PathPrefix(), rec.Handler(proxy.Handler(oktaAuthHandler(twirpServer))))

		// ONG-verified routes. The other routes are accessible via
		// blackbird.githubapp.com, too, but these verify that you are who you say
		// you are.
		const (
			reactRoot  = "./admin-frontend/build"
			reactIndex = reactRoot + "/index.html"
		)
		adminRouter := chi.NewRouter()
		adminRouter.Use(oktaAuthHandler)
		adminRouter.Use(cfg.SecurityHandler())
		adminRouter.Get("/", func(w http.ResponseWriter, r *http.Request) {
			http.ServeFile(w, r, reactIndex)
		})
		adminRouter.Mount("/static", mwhttp.NonListingFileServer(reactRoot))
		// All other URLs need to be handled by the React App and its internal routing
		adminRouter.Get("/*", func(rw http.ResponseWriter, r *http.Request) {
			http.ServeFile(rw, r, reactIndex)
		})
		mux.Mount("/", adminRouter)
	} else {
		// Just run the twirp admin service
		usernameHandler := cfg.OktaUsernameHandler()
		mux.Mount(twirpServer.PathPrefix(), rec.Handler(usernameHandler(twirpServer)))
	}

	return mux
}

type reverseProxy struct {
	stamps map[string]*httputil.ReverseProxy
}

func (p *reverseProxy) Handler(next http.Handler) http.Handler {
	const githubStampHeader = "X-GitHub-Stamp"
	return http.HandlerFunc(func(rw http.ResponseWriter, req *http.Request) {
		stamp := req.Header.Get(githubStampHeader)
		if rp, ok := p.stamps[stamp]; ok {
			req.Header.Del(githubStampHeader)
			rp.ServeHTTP(rw, req)
		} else {
			next.ServeHTTP(rw, req)
		}
	})
}

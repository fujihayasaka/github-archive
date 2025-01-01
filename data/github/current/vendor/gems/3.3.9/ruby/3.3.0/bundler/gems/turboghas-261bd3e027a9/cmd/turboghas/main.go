// Command turboghas runs a twirp service and optional stream processors for tracking Advanced Security active committer data.
package main

import (
	"context"
	stderrors "errors"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-ctxutil"
	"github.com/github/go-http/middleware/hmac"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-staffbar"
	"github.com/github/go-stats"
	twhooks "github.com/github/go-twirp/v2/server/hooks"
	twauth "github.com/github/go-twirp/v2/server/hooks/auth"
	twlog "github.com/github/go-twirp/v2/server/hooks/log"
	twstats "github.com/github/go-twirp/v2/server/hooks/stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/turboghas/cmd/turboghas/configuration"
	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/hydro_logger"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/internal/processor"
	"github.com/github/turboghas/internal/retry"
	"github.com/github/turboghas/internal/twirperr"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"
)

func do(ctx context.Context, startProcessor bool) (err error) {
	config, err := configuration.LoadConfiguration()
	if err != nil {
		return errors.Wrap(err, "failed to load config")
	}

	return config.WithContext(ctx, func(ctx context.Context) (err error) {
		defer func() {
			if fromctx.IsShuttingDown(ctx) {
				// we are happy to ignore the service being shut down intentionally
				err = nil
			}
		}()

		logger := fromctx.Logger.Value(ctx)
		statter := fromctx.Statter.Value(ctx)

		logger.Info("configuration loaded", kvp.Any("gh.app.env", fromctx.Env.Value(ctx)))

		db, err := mysql_dual.NewConnection(config.MySQLConfigs())
		if err != nil {
			return errors.Wrap(err, "failed to create MySQL connection")
		}
		defer func() {
			err = stderrors.Join(err, db.Close())
		}()

		group, ctx := errgroup.WithContext(ctx)

		if startProcessor {
			logger.Info("Starting hydro topic processor...", kvp.Any("brokers", config.Brokers))

			kafkaConfiguration, err := hydro.NewKafkaConfig(config.Brokers,
				hydro.WithKafkaVersion(config.KafkaVersion),
				hydro.WithKafkaLogger(hydro_logger.New(logger)),
				hydro.WithKafkaStats(statter),
				hydro.WithKafkaErrorReporter(fromctx.ExceptionReporter.Value(ctx)),
				hydro.WithClientID("turboghas"),
				config.KafkaTLS(),
			)
			if err != nil {
				return errors.Wrap(err, "could not create new Kafka config")
			}

			githubSigner, err := config.GitHubClient(ctx)
			if err != nil {
				return errors.Wrap(err, "could not create github client")
			}

			ghghAPI := twirpTurboghas.NewTurboghasAPIProtobufClient(config.GitHubTwirpURL, githubSigner, twirp.WithClientInterceptors(
				func(fn twirp.Method) twirp.Method {
					return func(ctx context.Context, request any) (any, error) {
						then := time.Now()
						defer func() {
							if name, ok := twirp.MethodName(ctx); ok {
								statter.Timing("api_request", stats.Tags{"method": name}, time.Since(then))
								statter.Counter("api_request.called", stats.Tags{"method": name}, 1)
							}
						}()
						return fn(ctx, request)
					}
				},
			))

			spokesTransport, err := config.SpokesTransport(ctx)
			if err != nil {
				return err
			}

			spokesdClient := config.RetryClient(ctx)
			spokesdClient.RetryMax = 5
			spokesdClient.RetryWaitMin = 5 * time.Second
			spokesdClient.RetryWaitMax = 30 * time.Second
			spokesdClient.HTTPClient = &http.Client{Transport: spokesTransport}

			commitsAPI := commits.NewCommitsAPIProtobufClient(config.SpokesdTwirpURL, spokesdClient.StandardClient())

			aqStatter, err := aqueduct.NewStatsConfig(aqueduct.WithStatsClient(statter))
			if err != nil {
				return err
			}

			aqueductHttpClient := config.RetryClient(ctx)
			aqueductHttpClient.RetryMax = 10
			aqueductHttpClient.RetryWaitMax = 5 * time.Minute
			aqueductHttpClient.HTTPClient = configuration.AppClient(ctx)

			aqueductOpts := []aqueduct.ClientOption{
				aqueduct.WithClientLogger(logger),
				aqueduct.WithClientStats(aqStatter),
				aqueduct.WithHTTPClient(aqueductHttpClient.StandardClient()),
			}

			if config.AqueductAPIKey != "" {
				aqueductOpts = append(aqueductOpts, aqueduct.WithAPIKey(config.AqueductAPIKey))
			}
			if config.AqueductAPIKeyVersion != 0 {
				aqueductOpts = append(aqueductOpts, aqueduct.WithAPIKeyVersion(config.AqueductAPIKeyVersion))
			}

			aqueductClient, err := aqueduct.NewClient(config.AqueductAddr, aqueductOpts...)
			if err != nil {
				return err
			}

			source, err := hydro.NewKafkaSource(*kafkaConfiguration, "turboghas", processor.Topics())
			if err != nil {
				return errors.Wrap(err, "could not create new Kafka source")
			}
			defer func() {
				if err := source.Close(); err != nil {
					logger.Error("Could not close Kafka source.", kvp.Any("error", err.Error()))

				}
			}()

			lowPrioritySource, err := hydro.NewKafkaSource(*kafkaConfiguration, "turboghas", processor.LowPriorityTopics())
			if err != nil {
				return errors.Wrap(err, "could not create new Kafka source")
			}
			defer func() {
				if err := lowPrioritySource.Close(); err != nil {
					logger.Error("Could not close Kafka source.", kvp.Any("error", err.Error()))

				}
			}()

			cacheInvalidationSource, err := hydro.NewKafkaSource(*kafkaConfiguration, "turboghas", processor.CacheInvalidationTopics())
			if err != nil {
				return errors.Wrap(err, "could not create new Kafka source")
			}
			defer func() {
				if err := cacheInvalidationSource.Close(); err != nil {
					logger.Error("Could not close Kafka source.", kvp.Any("error", err.Error()))

				}
			}()

			ignoreReplicationLagSource, err := hydro.NewKafkaSource(*kafkaConfiguration, "turboghas", processor.IgnoreReplicationLagTopics())
			if err != nil {
				return errors.Wrap(err, "could not create new Kafka source")
			}
			defer func() {
				if err := ignoreReplicationLagSource.Close(); err != nil {
					logger.Error("Could not close Kafka source.", kvp.Any("error", err.Error()))
				}
			}()

			sink, err := hydro.NewKafkaSink(*kafkaConfiguration)
			if err != nil {
				return errors.Wrap(err, "could not create new Kafka sink")
			}
			defer func() {
				if err := sink.Close(); err != nil {
					logger.Error("Could not close Kafka sink.", kvp.Any("error", err.Error()))
				}
			}()

			publisher, err := hydro.NewPublisher(sink, hydro.WithEncoder(hydro.NewDefaultEncoder()))
			if err != nil {
				return errors.Wrap(err, "could not create new publisher")
			}

			p := processor.New(data.New(db), ghghAPI, publisher, aqueductClient, processor.NewDependencies(commitsAPI))

			retrierConfig, err := aqueduct.NewRetrierConfig(
				// the built-in retry causes slow shutdown as it will continue to try and fetch a job even after the context
				// has been cancelled
				aqueduct.WithMaxRetries(0),
			)
			if err != nil {
				return errors.Wrap(err, "failed to create a retrier config")
			}

			{
				aqueductPipeline := processor.UnwrapAqueduct(retry.Handler(p.ProcessJob, func() backoff.BackOff {
					// never retry jobs in Aqueduct - they will be redelivered after timeout
					// wrapping in a retry handler ensures that errors are sent to Sentry
					return &backoff.StopBackOff{}
				}))
				worker, err := aqueduct.NewWorker(aqueductClient, "turboghas", processor.Queues(), aqueductPipeline,
					aqueduct.WithLogger(logger),
					aqueduct.WithRetrierConfig(retrierConfig),
					// we are using IgnoreJobErr to allow Aqueduct to take care of redelivery
					// after the message timeout is breached
					aqueduct.WithJobErrorPolicy(aqueduct.IgnoreJobErr),
				)
				if err != nil {
					return errors.Wrap(err, "failed to create aqueduct worker")
				}
				group.Go(func() error {
					log.Info("starting aqueduct worker")
					for ctx.Err() == nil {
						if processErr := worker.ProcessJob(ctx); processErr != nil {
							if !fromctx.IsShuttingDown(ctx) {
								fromctx.ExceptionReporter.Report(ctx, processErr, nil)
								logger.WithError(processErr).Error("error processing job")
							}
						}
					}
					return ctx.Err()
				})
			}

			processMessage := processor.UnwrapMessage(processor.UnwrapEnvelope(retry.Handler(p.ProcessMessage, fromctx.DefaultBackOff)))

			waitForLagAndProcessMessage := func(ctx context.Context, outer hydro.Message) error {
				if off, flipperErr := fromctx.Flipper.Value(ctx).IsGloballyEnabled(ctx, "turboghas_ignore_replication_lag"); flipperErr == nil && !off {
					if waitErr := fromctx.Lag.Wait(ctx, outer); waitErr != nil {
						fromctx.Logger.Value(ctx).WithError(waitErr).Error("could not wait for replication lag")
					}
				}
				return processMessage(ctx, outer)
			}

			group.Go(func() error {
				return errors.Wrap(source.Consume(ctx, waitForLagAndProcessMessage), "could not consume messages")
			})

			group.Go(func() error {
				return errors.Wrap(cacheInvalidationSource.Consume(ctx, waitForLagAndProcessMessage), "could not consume messages")
			})

			// create a second pipeline that does not attempt to wait for replication lag so we can keep processing messages for topics
			// that don't rely on external state even if there is a stall
			group.Go(func() error {
				return errors.Wrap(ignoreReplicationLagSource.Consume(ctx, processMessage), "could not consume messages")
			})

			// this is a single partition queue that one worker will plod away at
			// we already waited for replication lag on the original queue that received this message
			group.Go(func() error {
				return errors.Wrap(lowPrioritySource.Consume(ctx, processMessage), "could not consume messages from low priority source")
			})
		}

		// start the server that the monolith will request data from
		{
			hooks := []*twirp.ServerHooks{
				twhooks.TimingHooks(),
				twhooks.StoreTwirpErrorHooks(),
				twlog.DefaultHooks(logger),
				twstats.DefaultHooks(statter),
				{
					RequestReceived: func(ctx context.Context) (context.Context, error) {
						return fromctx.Logger.With(ctx, fromctx.Logger.Value(ctx).WithFields(twlog.DefaultFields(ctx)...)), nil
					},
					Error: func(ctx context.Context, twerr twirp.Error) context.Context {
						// prepare and send metrics
						tags := stats.Tags{
							"gh.turboghas.twirp_error_code": string(twerr.Code()),
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
						statter.Counter("server.unhandled.error", tags, 1)

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
						err := twirperr.LastCause(twerr)

						fromctx.Logger.Value(ctx).WithError(err).Error("request failed")
						fromctx.ExceptionReporter.Report(ctx, err, payload)

						return ctx
					},
				},
			}

			if len(config.HMACKeys) > 0 {
				hooks = append(hooks, twauth.VerifyRequestHMACHooks(config.HMACKeys...))
			}

			mux := http.NewServeMux()
			mux.HandleFunc("/_ping", func(w http.ResponseWriter, r *http.Request) {
				http.Error(w, "OK", http.StatusOK)
			})

			mux.Handle("/", api.New(db, hooks...))

			chain := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				hmac.Handler(requestid.Handler(staffbar.Handler(mux))).ServeHTTP(w, r)
			})

			// set up a chatops handler
			chatopsHandler, err := NewChatopsHandler(config)
			if err != nil {
				return err
			}
			mux.Handle("/_chatops", chatopsHandler)

			srv := &http.Server{
				Addr: config.Addr,
				BaseContext: func(listener net.Listener) context.Context {
					return ctxutil.DetachedCancel(ctx)
				},
				Handler:           chain,
				ReadTimeout:       5 * time.Second,
				ReadHeaderTimeout: 5 * time.Second,
				WriteTimeout:      10 * time.Second,
				IdleTimeout:       120 * time.Second,
			}

			group.Go(func() error {
				logger.Info("Starting server", kvp.String("addr", srv.Addr))
				return srv.ListenAndServe()
			})
			group.Go(func() error {
				<-ctx.Done()
				return srv.Shutdown(ctx)
			})
		}

		return group.Wait()
	})
}

func main() {
	var startProcessor bool
	flag.BoolVar(&startProcessor, "processor", false, "Run the hydro topic processor.")
	flag.Parse()

	if err := do(context.Background(), startProcessor); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Service terminated: %q", err)
		os.Exit(1)
	}
}

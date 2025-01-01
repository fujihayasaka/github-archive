// Command backfill reprocesses all the available PostReceive message since the last backfill.
package main

import (
	"context"
	stderrors "errors"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	v1 "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/turboghas/cmd/turboghas/configuration"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/hydro_logger"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/internal/processor"
	"github.com/github/turboghas/internal/retry"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"
)

func getUpto() (time.Time, error) {
	env := os.Getenv("TURBOGHAS_BACKFILL_UPTO")
	if env == "" {
		return time.Now(), nil
	}
	return time.Parse(time.RFC3339, env)
}

func do(ctx context.Context) (err error) {
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

		db, err := mysql_dual.NewConnection(config.MySQLConfigs())
		if err != nil {
			return errors.Wrap(err, "failed to create MySQL connection")
		}
		defer func() {
			err = stderrors.Join(err, db.Close())
		}()

		logger.Info("Starting hydro topic processor...", kvp.Any("brokers", config.Brokers))

		kafkaConfiguration, err := hydro.NewKafkaConfig(config.Brokers,
			hydro.WithKafkaVersion(config.KafkaVersion),
			hydro.WithKafkaLogger(hydro_logger.New(logger)),
			hydro.WithKafkaStats(statter),
			hydro.WithKafkaErrorReporter(fromctx.ExceptionReporter.Value(ctx)),
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
		spokesdClient.RetryMax = 10
		spokesdClient.RetryWaitMax = 5 * time.Minute
		spokesdClient.HTTPClient = &http.Client{Transport: spokesTransport}

		commitsAPI := commits.NewCommitsAPIProtobufClient(config.SpokesdTwirpURL, spokesdClient.StandardClient())

		source, err := hydro.NewKafkaSource(*kafkaConfiguration, "turboghas-backfill", []string{"cp1-iad.ingest.github.v1.PostReceive"})
		if err != nil {
			return errors.Wrap(err, "could not create new Kafka source")
		}

		p := processor.New(data.New(db), ghghAPI, nil, nil, processor.NewDependencies(commitsAPI))

		defer func() {
			if err := source.Close(); err != nil {
				logger.Error("Could not close Kafka source.", kvp.Any("error", err.Error()))
			}
		}()

		// use this environment variable to skip any messages after a RFC3339 timestamp
		// defaults to the time the backfill process was started
		upto, err := getUpto()
		if err != nil {
			return err
		}

		processEnvelope := processor.UnwrapEnvelope(retry.Handler(p.ProcessMessage, fromctx.DefaultBackOff))

		hydroPipeline := processor.UnwrapMessage(func(ctx context.Context, env *v1.Envelope) error {
			if env.GetTimestamp().AsTime().After(upto) {
				// skip any messages after the fix was deployed
				return nil
			}

			return processEnvelope(ctx, env)
		})

		return errors.Wrap(source.Consume(ctx, hydroPipeline), "could not consume messages")
	})
}

func main() {
	if err := do(context.Background()); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "Service terminated: %q", err)
		os.Exit(1)
	}
}

// Package metrics emits daily metrics about the Advanced Security active committers tracked by the system.
package main

import (
	"context"
	stderrors "errors"
	"flag"
	"fmt"
	"math"
	"os"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/turboghas/cmd/turboghas/configuration"
	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/api/ctes"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/hydro_logger"
	v1 "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/mysql_dual"
	"github.com/github/turboghas/internal/resync"
	"github.com/github/turboghas/proto"
	"github.com/pkg/errors"
	"github.com/simon-engledew/sqlh"
	"golang.org/x/exp/constraints"
	"golang.org/x/sync/errgroup"
	protobuf "google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func main() {
	if err := do(context.Background()); err != nil {
		fmt.Printf("level=error message=%q\n", err)
		os.Exit(1)
	}
}

func percent[N constraints.Float | constraints.Integer](v, total N) string {
	if total == 0 {
		return "n/a"
	}
	return fmt.Sprintf("%.0f%%", float64(v)/float64(total)*100)
}

type Publisher interface {
	Publish(m protoreflect.ProtoMessage, opts ...hydro.PublishOption) error
}

type summaryRequest struct {
	entityID uint64
	proto.GetSummaryRequest
}

func entityStats(ctx context.Context, buckets []int64, current, recent *proto.GetSummaryResponse) error {
	activity := strconv.FormatBool(current.ActiveCommitters > 0)

	logger := fromctx.Logger.Value(ctx).WithFields(kvp.String("activity", activity))
	statter := fromctx.Statter.Value(ctx)

	for i, contributors := range buckets {
		bucket := strconv.Itoa(i)
		ratio := float64(contributors) / float64(current.MaximumCommitters)
		logger.Info("contributors",
			kvp.Uint64("maximum", current.MaximumCommitters),
			kvp.Int("bucket", i),
			kvp.Int64("count", contributors),
			kvp.Float64("ratio", ratio),
		)
		statter.Counter("metrics.contributors.count", stats.Tags{"bucket": bucket, "activity": activity}, contributors)
		statter.Distribution("metrics.contributors.ratio", stats.Tags{"bucket": bucket, "activity": activity}, ratio)
	}

	if current.ActiveCommitters > 0 {
		ratio := float64(recent.ActiveCommitters) / float64(current.ActiveCommitters)
		statter.Distribution("metrics.recent_committer_ratio.active", stats.Tags{"activity": activity}, ratio)
		if ratio < 0.4 {
			logger.Info("entity has large change in active committers",
				kvp.Uint64("recent", recent.ActiveCommitters),
				kvp.Uint64("current", current.ActiveCommitters),
				kvp.Float64("ratio", ratio),
			)
		}
	}
	if current.MaximumCommitters > 0 {
		ratio := float64(recent.MaximumCommitters) / float64(current.MaximumCommitters)
		statter.Distribution("metrics.recent_committer_ratio.maximum", stats.Tags{"activity": activity}, ratio)
		if ratio < 0.4 {
			logger.Info("entity has large change in maximum committers",
				kvp.Uint64("recent", recent.MaximumCommitters),
				kvp.Uint64("current", current.MaximumCommitters),
				kvp.Float64("ratio", ratio),
			)
		}
	} else {
		logger.Info("entity has no maximum committers")
		statter.Counter("metrics.no_maximum_committers", nil, 1)
	}

	return nil
}

// committerDistribution creates a query that groups the committer numbers into zero-indexed buckets based on which week
// they became active, starting at the previous week and running backwards.
// E.g: If a user last pushed 4 weeks ago they would be included in bucket 3.
// This is helpful to spot spikes of committers aging out unexpectedly as usually the majority of committers should be in
// bucket 0 or 1.
func committerDistribution(ctx context.Context, req *proto.GetSummaryRequest) sqlh.Expr {
	bucketRange := make([]int, int(math.Floor(ctes.DefaultCommitterPeriodDays/7)))
	for i := range bucketRange {
		bucketRange[i] = i
	}

	contributors := ctes.SQL(`SELECT FLOOR(DATEDIFF(CURDATE(), MAX(pushed_at))/7) AS bucket FROM cte_contributions GROUP BY user_id HAVING user_id IN (?)`, ctes.BillableUsers)

	return ctes.WithContributions(ctx, req, ctes.SQL(`
SELECT count(_contributors.bucket)
FROM json_table(?, '$[*]' columns(bucket INT PATH '$')) _buckets
LEFT OUTER JOIN (?) AS _contributors ON _buckets.bucket = _contributors.bucket
GROUP BY _buckets.bucket
ORDER BY _buckets.bucket ASC`, sqlh.Json(bucketRange), contributors))
}

func summarize(ctx context.Context, db mysql_dual.QueryDB, publisher Publisher, batchSize int, now time.Time) error {
	logger := fromctx.Logger.Value(ctx)

	startedAt := timestamppb.New(now)

	progress := struct {
		entityID, maxEntityID uint64
	}{}

	handler := api.NewAdvancedSecurityAPI(db)

	g, groupCtx := errgroup.WithContext(ctx)

	// 1. fetch the entities to be summarized
	summaryRequests := make(chan *summaryRequest)
	g.Go(func() error {
		defer close(summaryRequests)

		return fromctx.Retry(groupCtx, func() error {
			for {
				rows, err := db.QueryContext(groupCtx, "SELECT id, (SELECT max(id) FROM tg_entities), entity_type, entity_id FROM tg_entities WHERE id > ? ORDER BY id LIMIT ?", progress.entityID, batchSize)
				if err != nil {
					return err
				}

				values, err := sqlh.Scan(rows, func(request *summaryRequest, row sqlh.Row) error {
					return row.Scan(&request.entityID, &progress.maxEntityID, &request.EntityType, &request.EntityId)
				})
				if err != nil {
					return err
				}

				for _, value := range values {
					summaryRequest := value
					summaryRequests <- summaryRequest
					progress.entityID = value.entityID
				}

				if len(values) == 0 {
					return nil
				}
			}
		}, fromctx.DefaultBackOff())
	})

	// 2. Lookup the entity summary information
	messages := make(chan protobuf.Message)

	workers, workerCtx := errgroup.WithContext(groupCtx)
	const WORKERS = 4
	for i := 0; i < WORKERS; i++ {
		workers.Go(func() error {
			for request := range summaryRequests {
				if err := fromctx.Retry(workerCtx, func() error {
					then := time.Now()

					current, err := handler.GetSummary(workerCtx, &request.GetSummaryRequest)
					if err != nil {
						return errors.Wrap(err, "failed to get summary")
					}

					entity := resync.Entity{ID: request.EntityId, Type: request.EntityType}

					entityLogger := logger.WithFields(
						kvp.Uint64("gh.turboghas.entity_id", request.EntityId),
						kvp.String("gh.turboghas.entity_type", request.EntityType.String()),
					)

					entityLogger.Info(
						"committer summary",
						kvp.Uint64("gh.turboghas.active_committers", current.ActiveCommitters),
						kvp.Uint64("gh.turboghas.maximum_committers", current.MaximumCommitters),
						kvp.String("gh.turboghas.progress", percent(request.entityID, progress.maxEntityID)),
						kvp.Duration("duration", time.Since(then)),
					)

					buckets, err := sqlh.Pluck[int64](committerDistribution(ctx, &request.GetSummaryRequest).QueryContext(ctx, db))
					if err != nil {
						return errors.Wrap(err, "could not calculate contribution distribution")
					}

					committersQuery := ctes.WithContributions(ctx, &request.GetSummaryRequest, ctes.SQL(`
SELECT user_id, MAX(active) AS active, MAX(pushed_at) AS pushed_at
FROM cte_contributions
GROUP BY user_id
HAVING user_id IN (?)`, ctes.BillableUsers))

					rows, err := committersQuery.QueryContext(ctx, db)
					if err != nil {
						return errors.Wrap(err, "failed to query committers")
					}

					committers, err := sqlh.Scan(rows, func(out *v0.Committers_Committer, row sqlh.Row) error {
						return row.Scan(&out.UserId, &out.Active, data.Timestamp(&out.PushedAt))
					})
					if err != nil {
						return errors.Wrap(err, "failed to fetch committers")
					}

					recent, err := handler.GetSummary(ctes.WithCommitterPeriod(ctx, 7), &request.GetSummaryRequest)
					if err != nil {
						return errors.Wrap(err, "failed to calculate recent committer data")
					}

					if err := entityStats(fromctx.Logger.With(workerCtx, entityLogger), buckets, current, recent); err != nil {
						return errors.Wrap(err, "failed to calculate entity stats")
					}

					// if everything worked we send to publisher
					messages <- &v0.Summary{
						EntityId:          entity.ID,
						EntityType:        v1.EntityModel(entity.Type).String(),
						ActiveCommitters:  current.ActiveCommitters,
						MaximumCommitters: current.MaximumCommitters,
						StartedAt:         startedAt,
					}

					messages <- &v0.Committers{
						EntityId:   entity.ID,
						EntityType: v1.EntityModel(entity.Type).String(),
						Committers: committers,
						StartedAt:  startedAt,
					}

					return nil
				}, fromctx.DefaultBackOff()); err != nil {
					return err
				}
			}

			return nil
		})
	}

	g.Go(func() error {
		defer close(messages)
		return workers.Wait()
	})

	// 3. Publish the summary information to hydro
	g.Go(func() error {
		totalActive, totalMaximum := int64(0), int64(0)
		for message := range messages {
			if err := fromctx.Retry(groupCtx, func() (err error) {
				if publishErr := publisher.Publish(message); publishErr != nil {
					return publishErr
				}
				if summary, ok := message.(*v0.Summary); ok {
					// if we successfully published then add the figures to the running total
					totalActive += int64(summary.ActiveCommitters)
					totalMaximum += int64(summary.MaximumCommitters)
				}
				return nil
			}, fromctx.DefaultBackOff()); err != nil {
				return err
			}
		}

		fromctx.Statter.Value(groupCtx).Gauge("metrics.total_committers.active", nil, totalActive)
		fromctx.Statter.Value(groupCtx).Gauge("metrics.total_committers.maximum", nil, totalMaximum)

		return nil
	})

	return g.Wait()
}

func do(ctx context.Context) error {
	flag.Parse()

	config, err := configuration.LoadConfiguration()
	if err != nil {
		return err
	}

	return config.WithContext(ctx, func(ctx context.Context) (err error) {
		statter := fromctx.Statter.Value(ctx)
		logger := fromctx.Logger.Value(ctx)

		db, err := mysql_dual.NewConnection(config.MySQLConfigs())
		if err != nil {
			return errors.Wrap(err, "failed to create MySQL connection")
		}
		defer func() {
			err = stderrors.Join(err, db.Close())
		}()

		kafkaConfiguration, err := hydro.NewKafkaConfig(config.Brokers,
			hydro.WithKafkaVersion(config.KafkaVersion),
			hydro.WithKafkaLogger(hydro_logger.New(logger)),
			hydro.WithKafkaStats(statter),
			config.KafkaTLS(),
		)
		if err != nil {
			return errors.Wrap(err, "could not create new Kafka config")
		}

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

		logger.Info("starting metrics")

		if stop, err := fromctx.Flipper.Value(ctx).IsGloballyEnabled(ctx, "turboghas_metrics_killswitch"); err != nil || stop {
			if err != nil {
				logger.WithError(err).Error("failed to check metrics feature flag")
			}
			return nil
		}

		// as of this comment there are 561,975 entities
		return summarize(ctx, db.Replica, publisher, 10_000, time.Now())
	})
}

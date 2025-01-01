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

type summary struct {
	maximumCommitters              uint64
	activeCommitters               uint64
	activeCodeScanningCommitters   uint64
	activeSecretScanningCommitters uint64
}

func entityStats(ctx context.Context, buckets []int64, current, recent summary) error {
	activity := strconv.FormatBool(current.activeCommitters > 0)

	logger := fromctx.Logger.Value(ctx).WithFields(kvp.String("activity", activity))
	statter := fromctx.Statter.Value(ctx)

	for i, contributors := range buckets {
		bucket := strconv.Itoa(i)
		ratio := float64(contributors) / float64(current.maximumCommitters)
		logger.Info("contributors",
			kvp.Uint64("maximum", current.maximumCommitters),
			kvp.Int("bucket", i),
			kvp.Int64("count", contributors),
			kvp.Float64("ratio", ratio),
		)
		statter.Counter("metrics.contributors.count", stats.Tags{"bucket": bucket, "activity": activity}, contributors)
		statter.Distribution("metrics.contributors.ratio", stats.Tags{"bucket": bucket, "activity": activity}, ratio)
	}

	if current.activeCommitters > 0 {
		ratio := float64(recent.activeCommitters) / float64(current.activeCommitters)
		statter.Distribution("metrics.recent_committer_ratio.active", stats.Tags{"activity": activity}, ratio)
		if ratio < 0.4 {
			logger.Info("entity has large change in active committers",
				kvp.Uint64("recent", recent.activeCommitters),
				kvp.Uint64("current", current.activeCommitters),
				kvp.Float64("ratio", ratio),
			)
		}
	}
	if current.maximumCommitters > 0 {
		ratio := float64(recent.maximumCommitters) / float64(current.maximumCommitters)
		statter.Distribution("metrics.recent_committer_ratio.maximum", stats.Tags{"activity": activity}, ratio)
		if ratio < 0.4 {
			logger.Info("entity has large change in maximum committers",
				kvp.Uint64("recent", recent.maximumCommitters),
				kvp.Uint64("current", current.maximumCommitters),
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

	contributors := ctes.SQL(`SELECT FLOOR(DATEDIFF(?, MAX(pushed_at))/7) AS bucket FROM cte_contributions GROUP BY user_id HAVING user_id IN (?)`, time.Now(), ctes.BillableUsers)

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

					current := summary{}

					// code_security_active and secret_protection_active are hacks for the summary job
					// turboghas should not know or care about SKUs, however moving the summary job to the monolith is out of scope
					// for the unbundle work given that we aim to replace turboghas with Licensify
					committersQuery := sqlh.SQL(`SELECT
	user_id,
	MAX((enabled & ?) != 0) AS active,
	MAX((enabled & ?) != 0) AS code_security_active,
	MAX((enabled & ?) != 0) AS secret_protection_active,
	MAX(pushed_at) AS pushed_at
FROM cte_contributions
GROUP BY user_id
HAVING user_id IN (?)`,
						v1.Feature_FEATURE_ALL,
						v1.Feature_FEATURE_CODE_SCANNING|v1.Feature_FEATURE_DEPENDABOT,
						v1.Feature_FEATURE_SECRET_SCANNING,
						ctes.BillableUsers,
					)

					summaryQuery := sqlh.SQL(`SELECT
	COUNT(1) AS 'maximum_committers',
	IFNULL(sum(active), 0) AS 'active_committers',
	IFNULL(sum(code_security_active), 0) AS 'code_security_active_committers',
	IFNULL(sum(secret_protection_active), 0) AS 'secret_protection_active_committers'
FROM (?) _committers`, committersQuery)

					if err := ctes.WithContributions(ctx, &request.GetSummaryRequest, summaryQuery).QueryRowContext(ctx, db).Scan(
						&current.maximumCommitters,
						&current.activeCommitters,
						&current.activeCodeScanningCommitters,
						&current.activeSecretScanningCommitters,
					); err != nil {
						return errors.Wrap(err, "failed to calculate summary")
					}

					entity := resync.Entity{ID: request.EntityId, Type: request.EntityType}

					entityLogger := logger.WithFields(
						kvp.Uint64("gh.turboghas.entity_id", request.EntityId),
						kvp.String("gh.turboghas.entity_type", request.EntityType.String()),
					)

					entityLogger.Info(
						"committer summary",
						kvp.Uint64("gh.turboghas.active_committers", current.activeCommitters),
						kvp.Uint64("gh.turboghas.maximum_committers", current.maximumCommitters),
						kvp.Uint64("gh.turboghas.active_code_scanning_committers", current.activeCodeScanningCommitters),
						kvp.Uint64("gh.turboghas.active_secret_scanning_committers", current.activeSecretScanningCommitters),
						kvp.String("gh.turboghas.progress", percent(request.entityID, progress.maxEntityID)),
						kvp.Duration("duration", time.Since(then)),
					)

					buckets, err := sqlh.Pluck[int64](committerDistribution(ctx, &request.GetSummaryRequest).QueryContext(ctx, db))
					if err != nil {
						return errors.Wrap(err, "could not calculate contribution distribution")
					}

					rows, err := ctes.WithContributions(ctx, &request.GetSummaryRequest, committersQuery).QueryContext(ctx, db)
					if err != nil {
						return errors.Wrap(err, "failed to query committers")
					}

					committers, err := sqlh.Scan(rows, func(out *v0.Committers_Committer, row sqlh.Row) error {
						var codeScanning, secretScanning bool
						return row.Scan(&out.UserId, &out.Active, &codeScanning, &secretScanning, data.Timestamp(&out.PushedAt))
					})
					if err != nil {
						return errors.Wrap(err, "failed to fetch committers")
					}

					var recent summary
					if err := ctes.WithContributions(ctes.WithCommitterPeriod(ctx, 7), &request.GetSummaryRequest, summaryQuery).QueryRowContext(ctx, db).Scan(
						&recent.maximumCommitters,
						&recent.activeCommitters,
						&recent.activeCodeScanningCommitters,
						&recent.activeSecretScanningCommitters,
					); err != nil {
						return errors.Wrap(err, "failed to calculate recent summary")
					}

					if err := entityStats(fromctx.Logger.With(workerCtx, entityLogger), buckets, current, recent); err != nil {
						return errors.Wrap(err, "failed to calculate entity stats")
					}

					// if everything worked we send to publisher
					messages <- &v0.Summary{
						EntityId:                       entity.ID,
						EntityType:                     v1.EntityModel(entity.Type).String(),
						ActiveCommitters:               current.activeCommitters,
						ActiveCodeScanningCommitters:   current.activeCodeScanningCommitters,
						ActiveSecretScanningCommitters: current.activeSecretScanningCommitters,
						MaximumCommitters:              current.maximumCommitters,
						StartedAt:                      startedAt,
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

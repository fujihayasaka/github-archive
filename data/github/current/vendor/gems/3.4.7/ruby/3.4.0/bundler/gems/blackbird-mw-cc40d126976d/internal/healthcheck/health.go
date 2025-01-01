package healthcheck

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/utils"
)

// HealthState is a summary of the health of a corpus
type HealthState int

const (
	HealthStateUnknown       HealthState = iota // Can't determine the health state
	HealthStateNotServing                       // Serving_ts or serving_offset = 0
	HealthStateMissingShards                    // Missing one or more shards
	HealthStateStale                            // System is lagging by over an hour: search results are stale
	HealthStateValid                            // All shards are healthy and the cluster is up to date
)

func (h HealthState) String() string {
	return []string{"unknown", "not-serving", "missing-shards", "stale", "valid"}[h]
}

func (h HealthState) StatsTag() string {
	if h == HealthStateValid {
		return "healthy"
	}
	return "unhealthy"
}

type ClusterHealthSummary struct {
	HealthState HealthState
	ServingLag  time.Duration
	IngestLag   time.Duration
	Status      *routing.ClusterStatusSummary
}

func (p *Prober) ComputeHealthSummary(ctx context.Context, corpus routing.Corpus) (*ClusterHealthSummary, error) {
	if p.tsReader == nil {
		return nil, fmt.Errorf("no tsReader configured")
	}

	// 1. Compute the lag on the source kafka topics.
	// NB: We pull source kafka offsets from the indexAPI to get real-time info.
	indexSummary, err := p.indexerClusters.Status(ctx, corpus)
	if err != nil {
		return nil, fmt.Errorf("failed to get index cluster status: %w", err)
	}
	ctx = statting.WithTags(ctx, stats.Tags{"corpus": corpus.String(), "cluster": corpus.ClusterName(), "epoch_mode": indexSummary.EpochMode.String()})
	var maxIngestLag time.Duration
	for hostname, host := range indexSummary.HostStatuses {
		for _, shard := range host.Shards {
			// Compute the lag between the timestamp of the last consumed source message and the source
			// topic timestamp on a delay.
			consumed, ok := shard.SourceKafkaInfo[routing.IncrementalSourceConsumed]
			if ok {
				for partition, msg := range consumed.Partitions {
					lag := 0 * time.Second
					ts := utils.TimeFromServingTs(msg.Timestamp)
					if !ts.IsZero() {
						// NB: a zero timestamp means we've never published a consumed offset for this
						// partition, don't report any lag in that case
						lag = p.tsReader.Since(ts, partition)
					}
					logging.Info(ctx, "read source offsets from index host",
						kvp.Int("partition", int(partition)),
						kvp.Int("offset", int(msg.Offset)),
						kvp.String("index_host", hostname),
						kvp.Int("index_shard", int(shard.Id)),
						kvp.Duration("lag", lag),
					)
					statting.Gauge(ctx, "prober.delayed_consumed_source_lag", lag.Milliseconds(), stats.Tags{"partition": fmt.Sprintf("%d", partition), "index_host": hostname, "index_shard": fmt.Sprintf("%d", shard.Id)})
					if lag > maxIngestLag {
						maxIngestLag = lag
					}
				}
			}
		}
	}

	// 2. Compute the serving lag according to the search cluster (not the indexAPI)
	summary, err := p.searchClusters.Status(ctx, corpus)
	if err != nil {
		return nil, fmt.Errorf("failed to get search cluster status: %w", err)
	}
	var maxServingLag time.Duration
	for hostname, host := range summary.HostStatuses {
		for _, shard := range host.Shards {
			consumed, ok := shard.SourceKafkaInfo[routing.IncrementalSourceConsumed]
			if ok {
				for partition, msg := range consumed.Partitions {
					lag := 0 * time.Second
					ts := utils.TimeFromServingTs(msg.Timestamp)
					if !ts.IsZero() {
						// NB: a zero timestamp means we've never published a consumed offset for this
						// partition, don't report any lag in that case
						lag = p.tsReader.Since(ts, partition)
					}
					statting.Gauge(ctx, "prober.delayed_consumed_serving_lag", lag.Milliseconds(), stats.Tags{"partition": fmt.Sprintf("%d", partition), "index_host": hostname, "index_shard": fmt.Sprintf("%d", shard.Id)})
					if lag > maxServingLag {
						maxServingLag = lag
					}
				}
			}
		}
	}

	// Stat summary lag numbers
	getHealthTag := func(lag time.Duration) string {
		switch {
		case summary.ServingOffset == 0 || summary.ServingTs.IsZero():
			return "not-serving"
		case lag > 1*time.Hour:
			return "stale"
		case lag > 30*time.Minute:
			return "delayed"
		default:
			return "healthy"
		}
	}
	statting.Counter(ctx, "prober.delayed_consumed_serving_lag.corpus_status", 1, stats.Tags{"status": getHealthTag(maxServingLag)})
	statting.Counter(ctx, "prober.delayed_consumed_source_lag.corpus_status", 1, stats.Tags{"status": getHealthTag(maxIngestLag)})

	// Compute overall health state
	const maxStaleness = 1 * time.Hour
	var healthState HealthState
	switch {
	case summary.ServingOffset == 0 || summary.ServingTs.IsZero():
		healthState = HealthStateNotServing
	case summary.NumUnavailableShards > 0:
		healthState = HealthStateMissingShards
	case maxIngestLag > maxStaleness:
		healthState = HealthStateStale
	default:
		healthState = HealthStateValid
	}

	return &ClusterHealthSummary{
		HealthState: healthState,
		ServingLag:  maxServingLag,
		IngestLag:   maxIngestLag,
		Status:      summary,
	}, nil
}

package deltaingest

import (
	"context"
	"time"

	"github.com/cenkalti/backoff/v4"
	indexpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/index/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/retry"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

func newOffsetReporter(indexerCluster *routing.IndexerCluster, offsetTracker *kafka.OffsetTracker) offsetReporter {
	return offsetReporter{
		indexerCluster: indexerCluster,
		offsetTracker:  offsetTracker,
		epochID:        types.EpochID(indexerCluster.EpochInfo().EpochID), // Initial epoch ID, if it changes sendConsumedOffsets returns an error
	}
}

type offsetReporter struct {
	indexerCluster *routing.IndexerCluster
	offsetTracker  *kafka.OffsetTracker
	epochID        types.EpochID
}

func (o offsetReporter) sendConsumedOffsets(ctx context.Context) error {
	attempt := 0
	op := func() error {
		attempt++
		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
		defer cancel()

		if o.indexerCluster.IsIndexingPaused() {
			return nil
		}

		host, err := o.indexerCluster.GetHost()
		if err != nil {
			logging.Error(ctx, "failed to get host for index cluster, retrying", kvp.Err(err))
			return err
		}

		req := &indexpb.SkipRequest{
			ShardId:            host.ShardID,
			EpochId:            uint32(o.epochID),
			SourceKafkaOffsets: getAllSourceOffsets(o.offsetTracker),
		}

		_, err = host.Skip(ctx, req)
		if err != nil {
			logging.Error(ctx, "Skip RPC failed", kvp.Err(err), kvp.Int("skip_rpc_attempt", attempt), kvp.String("index_host", host.Hostname))
			if epochMovedErr := getNewEpochError(ctx, o.epochID, err); epochMovedErr != nil {
				return backoff.Permanent(epochMovedErr)
			}
			return err
		}

		return nil
	}

	return backoff.Retry(op, retry.Forever(ctx))
}

package ingest

import (
	"context"
	"testing"
	"time"

	"github.com/IBM/sarama"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/kafka/kafkafakes"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_getAllSourceOffsets(t *testing.T) {
	ts := time.Now()
	indexerCluster := helpers.IndexerCluster(t)
	corpus := helpers.Corpus(t)
	epochID := types.EpochID(indexerCluster.EpochInfo().EpochID)
	saramaClient := &mocks.FakeSaramaClient{}
	saramaClient.PartitionsReturns([]int32{0, 1}, nil) // return two partitions
	saramaClient.GetOffsetReturns(lagThreshold+1, nil) // end offset of partition
	clusterAdmin := &mocks.FakeClusterAdmin{}
	clusterAdmin.ListConsumerGroupsStub = func() (map[string]string, error) {
		return map[string]string{corpus.ConsumerGroup(epochID): "ignored metadata"}, nil
	}
	// this is the current offset of this consumer group. Lag = end offset - current offset
	clusterAdmin.ListConsumerGroupOffsetsStub = func(cg string, topics map[string][]int32) (*sarama.OffsetFetchResponse, error) {
		offsets := map[string]map[int32]*sarama.OffsetFetchResponseBlock{
			routing.IncrementalSourceTopic: {
				0: {Offset: 0},
				1: {Offset: lagThreshold / 2}, // within lag threshold
			},
			routing.OnboardSourceTopic: {
				0: {Offset: 0},
				1: {Offset: lagThreshold / 2}, // within lag threshold
			},
			corpus.EpochBackfillTopic(epochID): { // used for lag reporting, not otherwise part of test
				0: {Offset: 123},
				1: {Offset: 456},
			},
		}
		return &sarama.OffsetFetchResponse{Blocks: offsets}, nil
	}

	makeAdminClient := func() sarama.ClusterAdmin {
		return clusterAdmin
	}
	adminClient := kafka.NewAdminClient(makeAdminClient, saramaClient)
	offsetTracker := kafka.NewOffsetTracker(&kafkafakes.FakeIngestConsumer{})
	// NOTE: cheat and use same admin client for shared and blackbird Kafka clusters
	offsetReporter := newOffsetReporter(corpus, indexerCluster, offsetTracker, adminClient, adminClient)
	skos, err := offsetReporter.getAllSourceOffsets(context.Background())
	require.NoError(t, err)

	// No offsets have been tracked yet in the offset tracker, but we should still have SourceKafkaOffsets for the caught-up partitions.
	expected := []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
		{
			Topic: routing.OnboardSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
	}
	require.ElementsMatch(t, expected, skos)

	// Now, track some offsets. They should be reported as consumed and they will be unmarked.
	// The lag-based measurements remain marked.
	offsetTracker.TrackMsg(context.Background(), routing.IncrementalSourceTopic, 0, kafka.NewMarkedKafkaOffset(0), ts)
	offsetTracker.TrackMsg(context.Background(), routing.IncrementalSourceTopic, 0, kafka.NewMarkedKafkaOffset(1), ts)
	offsetTracker.MarkOffset(context.Background(), routing.IncrementalSourceTopic, 0, kafka.NewMarkedKafkaOffset(1))
	offsetTracker.TrackMsg(context.Background(), routing.OnboardSourceTopic, 0, kafka.NewMarkedKafkaOffset(0), ts)
	offsetTracker.TrackMsg(context.Background(), routing.OnboardSourceTopic, 0, kafka.NewMarkedKafkaOffset(1), ts)
	offsetTracker.MarkOffset(context.Background(), routing.OnboardSourceTopic, 0, kafka.NewMarkedKafkaOffset(1))
	skos, err = offsetReporter.getAllSourceOffsets(context.Background())
	require.NoError(t, err)

	expected = []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    0, // we have not been able to commit yet
				},
			},
		},
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(), // based on lag, see above
				},
			},
		},
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    1,
					Timestamp: ts.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.OnboardSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    0, // we have not been able to commit yet
				},
			},
		},
		{
			Topic: routing.OnboardSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(), // based on lag, see above
				},
			},
		},
		{
			Topic: routing.ConsumedTopic(routing.OnboardSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    1,
					Timestamp: ts.UnixMilli(),
				},
			},
		},
	}

	require.ElementsMatch(t, expected, skos, "OffsetTracker: %s", offsetTracker.String())

	// Now, track some offsets from the partitions that were added by the lag report.
	//
	// NOTE: They will be unmarked! That's because the marked offsets above were added by the lag tracking.
	// This is expected and OK: the indexer preserves the mark when updating offsets.
	offsetTracker.TrackMsg(context.Background(), routing.IncrementalSourceTopic, 1, kafka.NewMarkedKafkaOffset(0), ts)
	offsetTracker.MarkOffset(context.Background(), routing.IncrementalSourceTopic, 1, kafka.NewMarkedKafkaOffset(0))
	offsetTracker.TrackMsg(context.Background(), routing.OnboardSourceTopic, 1, kafka.NewMarkedKafkaOffset(0), ts)
	offsetTracker.MarkOffset(context.Background(), routing.OnboardSourceTopic, 1, kafka.NewMarkedKafkaOffset(0))
	skos, err = offsetReporter.getAllSourceOffsets(context.Background())
	require.NoError(t, err)

	expected = []*blackbird_entities.SourceKafkaOffsets{
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    0, // we have not been able to commit yet
				},
			},
		},
		{
			Topic: routing.IncrementalSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    1, // message with offset 0 was committed, committed is +1. Not marked!
				},
			},
		},
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    1,
					Timestamp: ts.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.ConsumedTopic(routing.IncrementalSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    0,
					Timestamp: ts.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.OnboardSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    0, // we have not been able to commit yet
				},
			},
		},
		{
			Topic: routing.OnboardSourceTopic,
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    1, // message with offset 0 was committed, committed is +1. Not marked!
				},
			},
		},
		{
			Topic: routing.ConsumedTopic(routing.OnboardSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 0,
					Offset:    1,
					Timestamp: ts.UnixMilli(),
				},
			},
		},
		{
			Topic: routing.ConsumedTopic(routing.OnboardSourceTopic),
			PartitionOffsets: []*blackbird_entities.SourceKafkaOffsets_PartitionOffset{
				{
					Partition: 1,
					Offset:    0,
					Timestamp: ts.UnixMilli(),
				},
			},
		},
	}
	require.ElementsMatch(t, expected, skos, "OffsetTracker: %s", offsetTracker.String())

}

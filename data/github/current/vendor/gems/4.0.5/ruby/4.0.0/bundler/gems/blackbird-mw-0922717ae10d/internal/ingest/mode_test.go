package ingest

import (
	"fmt"
	"testing"

	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

// It doesn't matter if all the incremental partitions are marked. If the
// backfill topic isn't marked, stay in backfill mode.
func Test_IngestModeFromSourceKafkaInfo(t *testing.T) {
	corpus := helpers.Corpus(t)
	epochID := types.EpochID(999)
	tc := routing.TopicConfig{
		Backfill: routing.BackfillTopicConfig{
			Partitions: 2,
		},
		Onboard: routing.OnboardTopicConfig{
			Partitions: 2,
		},
		Incremental: routing.IncrementalTopicConfig{
			Partitions: 2,
		},
	}

	kafkaInfo := map[string]*servingpb.KafkaInfo{
		corpus.EpochBackfillTopic(epochID): {
			Partitions: map[int32]*servingpb.OffsetTimestamp{
				0: {
					Offset: 0,
				},
				1: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
		routing.OnboardSourceTopic: {
			Partitions: map[int32]*servingpb.OffsetTimestamp{
				0: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
				1: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
		routing.IncrementalSourceTopic: {
			Partitions: map[int32]*servingpb.OffsetTimestamp{
				0: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
				1: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
	}

	ingestMode := IngestModeFromSourceKafkaInfo(kafkaInfo, corpus, epochID, epoch.EpochModeLexical, tc)
	require.Equal(t, db.IngestModeBackfill, ingestMode)

	// if we try this with an external epoch mode, it also says backfill, because the backfill topic matching is fuzzy and the offsets aren't marked yet.
	ingestMode = IngestModeFromSourceKafkaInfo(kafkaInfo, corpus, epochID, epoch.EpochModeExternalMetisEmbeddings, tc)
	require.Equal(t, db.IngestModeBackfill, ingestMode)
}

func Test_IngestModeFromSourceKafkaInfoExternalIngest(t *testing.T) {
	corpus := helpers.Corpus(t)
	epochID := types.EpochID(999)
	tc := routing.TopicConfig{
		Backfill: routing.BackfillTopicConfig{
			Partitions: 2,
		},
		External: routing.ExternalTopicConfig{
			Partitions: 2,
		},
	}

	kafkaInfo := map[string]*servingpb.KafkaInfo{
		fmt.Sprintf("blackbird.v1.external.Backfill.%s.%d", corpus, epochID): {
			Partitions: map[int32]*servingpb.OffsetTimestamp{
				0: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
				1: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
		routing.ExternalIncrementalSourceTopic: {
			Partitions: map[int32]*servingpb.OffsetTimestamp{
				0: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
				1: {
					Offset: helpers.MarkedKafkaOffsetWithMark(t, 0).Raw(),
				},
			},
		},
	}

	ingestMode := IngestModeFromSourceKafkaInfo(kafkaInfo, corpus, epochID, epoch.EpochModeExternalMetisEmbeddings, tc)
	require.Equal(t, db.IngestModeIncremental, ingestMode)

	// if we try this with a non-external ingest mode, it says backfill catchup because there's no matching incremental offsets
	ingestMode = IngestModeFromSourceKafkaInfo(kafkaInfo, corpus, epochID, epoch.EpochModeLexical, tc)
	require.Equal(t, db.IngestModeBackfillCatchup, ingestMode)
}

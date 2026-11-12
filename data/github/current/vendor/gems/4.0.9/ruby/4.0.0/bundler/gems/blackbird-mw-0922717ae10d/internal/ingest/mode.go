package ingest

import (
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

func IngestModeFromSourceKafkaInfo(kafkaInfo map[string]*servingpb.KafkaInfo, corpus routing.Corpus, epochID types.EpochID, epochMode epoch.EpochMode, tc routing.TopicConfig) db.IngestMode {
	backfillMarked := allBackfillOffsetsMarked(kafkaInfo, tc)
	incrMarked := allIncrementalOffsetsMarked(kafkaInfo, tc, epochMode)

	if !backfillMarked {
		return db.IngestModeBackfill
	} else if incrMarked {
		return db.IngestModeIncremental
	} else {
		return db.IngestModeBackfillCatchup
	}
}

func allIncrementalOffsetsMarked(sourceKafkaInfo map[string]*servingpb.KafkaInfo, tc routing.TopicConfig, epochMode epoch.EpochMode) bool {
	if epoch.EpochFeaturesExternalContent.SupportedBy(epochMode) {
		incrInfo, ok := sourceKafkaInfo[routing.ExternalIncrementalSourceTopic]
		if !ok {
			return false
		}

		for partition := range tc.External.Partitions {
			offsetTimestamp, ok := incrInfo.Partitions[partition]
			if !ok {
				return false
			}
			offset := kafka.NewMarkedKafkaOffsetFromRaw(offsetTimestamp.Offset)
			if !offset.IsMarked() {
				return false
			}
		}

		return true
	} else {
		onboardingInfo, ok := sourceKafkaInfo[routing.OnboardSourceTopic]
		if !ok {
			return false
		}

		for partition := range tc.Onboard.Partitions {
			offsetTimestamp, ok := onboardingInfo.Partitions[partition]
			if !ok {
				return false
			}
			offset := kafka.NewMarkedKafkaOffsetFromRaw(offsetTimestamp.Offset)
			if !offset.IsMarked() {
				return false
			}
		}

		incrInfo, ok := sourceKafkaInfo[routing.IncrementalSourceTopic]
		if !ok {
			return false
		}

		for partition := range tc.Incremental.Partitions {
			offsetTimestamp, ok := incrInfo.Partitions[partition]
			if !ok {
				return false
			}
			offset := kafka.NewMarkedKafkaOffsetFromRaw(offsetTimestamp.Offset)
			if !offset.IsMarked() {
				return false
			}
		}

		return true
	}
}

func allBackfillOffsetsMarked(sourceKafkaInfo map[string]*servingpb.KafkaInfo, tc routing.TopicConfig) bool {
	var backfillInfo *servingpb.KafkaInfo
	for topic, info := range sourceKafkaInfo {
		if routing.IsBackfillTopic(topic) {
			backfillInfo = info
		}
	}

	if backfillInfo == nil {
		return false
	}

	for partition := range tc.Backfill.Partitions {
		offsetTimestamp, ok := backfillInfo.Partitions[partition]
		if !ok {
			return false
		}
		offset := kafka.NewMarkedKafkaOffsetFromRaw(offsetTimestamp.Offset)
		if !offset.IsMarked() {
			return false
		}
	}

	return true
}

package routing

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/IBM/sarama"
	"github.com/github/blackbird/crates/core/pkg/shard"
	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/types"
)

// DocumentTopic describes the Kafka topic used to publish documents for blackbird-indexer.
type DocumentTopic struct {
	Corpus     Corpus
	EpochID    types.EpochID
	Partitions int32
}

// Name returns the string name of the DocumentTopic in Kafka.
func (o *DocumentTopic) Name() string {
	return fmt.Sprintf("blackbird.v1.GitDocument.%s.%d", o.Corpus.String(), o.EpochID)
}

func (o *DocumentTopic) PartitionForSHA(oid gitaccess.ObjectID) (int32, error) {
	if o.Partitions == 0 {
		return 0, errors.New("must be at least one partition")
	}

	shardID, err := shard.ShardID(uint(o.Partitions), oid.Bytes())
	if err != nil {
		return 0, err
	}

	return int32(shardID), nil

}

var ErrNotEpochTopic = errors.New("not an epoch topic")

// NewDocumentTopicFromTopicDetail takes a topic name and TopicDetail and
// returns a DocumentTopic if the topic name matches the pattern:
// blackbird.v1.GitDocument.<corpus>.<epoch_id>
func NewDocumentTopicFromTopicDetail(topic string, detail sarama.TopicDetail) (*DocumentTopic, error) {
	trimmed := strings.TrimPrefix(topic, "blackbird.v1.GitDocument.")
	segments := strings.Split(trimmed, ".")
	if len(segments) != 2 {
		return nil, ErrNotEpochTopic
	}

	corpus, err := CorpusFromString(segments[0])
	if err != nil {
		return nil, ErrNotEpochTopic
	}

	id, err := strconv.ParseUint(segments[1], 10, 32)
	if err != nil {
		return nil, ErrNotEpochTopic
	}

	return &DocumentTopic{
		Corpus:     corpus,
		EpochID:    types.EpochID(id),
		Partitions: detail.NumPartitions,
	}, nil
}

// SnapshotTopic describes the Kafka topic used to publish tree updates for blackbird-indexer.
type SnapshotTopic struct {
	Corpus  Corpus
	EpochID types.EpochID
}

// Name returns the string name of the snapshot topic in Kafka.
func (s *SnapshotTopic) Name() string {
	return fmt.Sprintf("blackbird.v1.SnapshotTreeUpdate.%s.%d", s.Corpus.String(), s.EpochID)
}

var ErrNotSnapshotTopic = errors.New("not a snapshot topic")

// NewSnapshotTopicFromTopicDetail returns a pointer to a SnapshotTopic if the
// input is represents one or an error.
func NewSnapshotTopicFromTopicDetail(topic string, detail sarama.TopicDetail) (*SnapshotTopic, error) {
	trimmed := strings.TrimPrefix(topic, "blackbird.v1.SnapshotTreeUpdate.")
	segments := strings.Split(trimmed, ".")

	if len(segments) != 2 {
		return nil, ErrNotSnapshotTopic
	}

	corpus, err := CorpusFromString(segments[0])
	if err != nil {
		return nil, ErrNotSnapshotTopic
	}

	id, err := strconv.ParseUint(segments[1], 10, 32)
	if err != nil {
		return nil, ErrNotSnapshotTopic
	}

	return &SnapshotTopic{
		Corpus:  corpus,
		EpochID: types.EpochID(id),
	}, nil
}

// TopicConfig defines the settings topics. Used for creating/modifying topics
// and figuring out partitioning.
type TopicConfig struct {
	Document    DocumentTopicConfig
	Snapshot    SnapshotTopicConfig
	Backfill    BackfillTopicConfig
	Onboard     OnboardTopicConfig
	Incremental IncrementalTopicConfig
}

type DocumentTopicConfig struct {
	ReplicationFactor          int16
	NewRetentionBytes          int // Per-partition retention of newly created topics (see Kafka's retention.bytes).
	NewRetentionDuration       time.Duration
	TruncatedRetentionBytes    int // Per-partition retention of old topics (see Kafka's retention.bytes).
	TruncatedRetentionDuration time.Duration
}

type SnapshotTopicConfig struct {
	ReplicationFactor int16
}

type BackfillTopicConfig struct {
	Partitions        int32
	ReplicationFactor int16
	RetentionDuration time.Duration
	RetentionBytes    int
}

type OnboardTopicConfig struct {
	Partitions int32
}

type IncrementalTopicConfig struct {
	Partitions int32
}

func (tc TopicConfig) DocumentTopicDetail(numPartitions int32) *sarama.TopicDetail {
	return &sarama.TopicDetail{
		NumPartitions:     numPartitions,
		ReplicationFactor: tc.Document.ReplicationFactor,
		ConfigEntries: map[string]*string{
			"retention.bytes": strptr(strconv.Itoa(tc.Document.NewRetentionBytes)),
			"retention.ms":    strptr(strconv.FormatInt(tc.Document.NewRetentionDuration.Milliseconds(), 10)),
		},
	}
}

func (tc TopicConfig) TruncateDocumentTopicConfig() map[string]*string {
	return map[string]*string{
		"retention.ms":    strptr(strconv.FormatInt(tc.Document.TruncatedRetentionDuration.Milliseconds(), 10)),
		"retention.bytes": strptr(strconv.Itoa(tc.Document.TruncatedRetentionBytes)),
	}
}

func (tc TopicConfig) SnapshotTopicDetail() *sarama.TopicDetail {
	return &sarama.TopicDetail{
		NumPartitions:     1,
		ReplicationFactor: tc.Snapshot.ReplicationFactor,
	}
}

func (tc TopicConfig) BackfillTopicDetail() *sarama.TopicDetail {
	return &sarama.TopicDetail{
		NumPartitions:     tc.Backfill.Partitions,
		ReplicationFactor: tc.Backfill.ReplicationFactor,
		ConfigEntries: map[string]*string{
			"retention.bytes": strptr(strconv.Itoa(tc.Backfill.RetentionBytes)),
			"retention.ms":    strptr(strconv.FormatInt(tc.Backfill.RetentionDuration.Milliseconds(), 10)),
		},
	}
}

// BackfillTopicNumPartitions is the number of partitions in the backfill
// topics.
//
// Defaults to 1 to support testing, the config system sets this on boot. Do not
// change it after that.
var BackfillTopicNumPartitions uint32 = 1

func strptr(s string) *string {
	return &s
}

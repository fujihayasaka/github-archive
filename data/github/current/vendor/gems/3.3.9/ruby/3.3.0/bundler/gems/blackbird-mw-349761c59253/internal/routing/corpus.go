package routing

import (
	"fmt"
	"strings"

	"github.com/pkg/errors"

	"github.com/github/blackbird-mw/internal/types"
)

// Corpus is a custom type to hold the value of the corpus for indexing/search.
// A corpus allows capturing the state required to build and incrementally
// maintain a search index between blackbird-mw and a cluster of blackbird
// indexing shards.
//
// Its values are stored in the database, so DO NOT reorder or delete them!
type Corpus int

const (
	Blue Corpus = iota
	Green
	Yellow
	Red
	Orange
	Violet
)

var Corpora = []Corpus{Blue, Green, Yellow, Red, Orange, Violet}

func (c Corpus) String() string {
	return [...]string{"Blue", "Green", "Yellow", "Red", "Orange", "Violet"}[c]
}

func (c Corpus) EnabledInStamp(s Stamp) bool {
	switch s {
	case Dotcom:
		return true
	default:
		return c == Blue || c == Green
	}
}

func (c Corpus) DisabledInStamp(s Stamp) bool {
	return !c.EnabledInStamp(s)
}

func (c Corpus) NameWithCluster() string {
	return fmt.Sprintf("%s/%s", c.ClusterName(), strings.ToLower(c.String()))
}

func CorpusFromString(name string) (Corpus, error) {
	name = strings.ToLower(name)
	for _, corpus := range Corpora {
		if strings.ToLower(corpus.String()) == name {
			return corpus, nil
		}
	}
	return -1, fmt.Errorf("invalid corpus name %s", name)
}

func CorpusFromCluster(name string) (Corpus, error) {
	for _, corpus := range Corpora {
		if name == corpus.ClusterName() {
			return corpus, nil
		}
	}

	return -1, fmt.Errorf("invalid cluster name %q", name)
}

func GetOtherCorpora(corpus Corpus) []Corpus {
	var corpora []Corpus
	for _, c := range Corpora {
		if c == corpus {
			continue
		}

		corpora = append(corpora, c)
	}

	return corpora
}

// The incremental topics for all corpora.
const (
	// The `RepositoryChanged` topic that tracks repo pushes and all other events.
	IncrementalSourceTopic string = "cp1-iad.ingest.github.search.v0.RepositoryChanged"
	// The `BlackbirdOnboard` topic that's used to add new repositories to the index.
	OnboardSourceTopic string = "blackbird.v0.BlackbirdOnboard"

	// A fake kafka topic used by the indexers to track consumed (vs. committed) offsets on the
	// incremental source topic (RepositoryChanged). Be careful, this topic does not exist in Kafka
	// and has invalided characters in it.
	IncrementalSourceConsumed string = IncrementalSourceTopic + "^consumed"
)

const Text3SmallInference = "text-embedding-3-small"

// There is currently a 1:1 mapping between corpus and cluster in our system.
// This might not always be the case, but the following map will suffice for
// now.
var clusterNames = map[Corpus]string{
	Blue:   "zeta",
	Green:  "eta",
	Yellow: "theta",
	Red:    "iota",
	Orange: "kappa",
	Violet: "lambda",
}

// Names of cache clusters. Cache clusters don't belong to a particular corpus.
var (
	cacheCluster001 = "cache-001"
	cacheCluster002 = "cache-002"
	cacheCluster003 = "cache-003"
	cacheCluster004 = "cache-004"
)

// TODO: Get rid of this after removing special case naming for original cache cluster
var cacheAssignmentTopics = map[string]string{
	cacheCluster001: "blackbird.v0.cache001.ShardAssignment",
	cacheCluster002: "blackbird.v0.cache002.ShardAssignment",
	cacheCluster003: "blackbird.v0.cache003.ShardAssignment",
	cacheCluster004: "blackbird.v0.cache004.ShardAssignment",
}
var cacheAssignmentSnapshotTopics = map[string]string{
	cacheCluster001: "blackbird.v0.cache001.ShardAssignmentSnapshot",
	cacheCluster002: "blackbird.v0.cache002.ShardAssignmentSnapshot",
	cacheCluster003: "blackbird.v0.cache003.ShardAssignmentSnapshot",
	cacheCluster004: "blackbird.v0.cache004.ShardAssignmentSnapshot",
}

var CacheClusterNames = []string{cacheCluster001, cacheCluster002, cacheCluster003, cacheCluster004}

func IsCacheCluster(name string) bool {
	for _, cacheCluster := range CacheClusterNames {
		if name == cacheCluster {
			return true
		}
	}

	return false
}

func ShardAssignmentTopicForCluster(cluster string) (string, error) {
	if IsCacheCluster(cluster) {
		return cacheAssignmentTopics[cluster], nil
	}

	corpus, err := CorpusFromCluster(cluster)
	if err != nil {
		return "", err
	}

	return corpus.ShardAssignmentTopic(), nil
}

func ShardAssignmentSnapshotTopicForCluster(cluster string) (string, error) {
	if IsCacheCluster(cluster) {
		return cacheAssignmentSnapshotTopics[cluster], nil
	}

	corpus, err := CorpusFromCluster(cluster)
	if err != nil {
		return "", err
	}

	return corpus.ShardAssignmentSnapshotTopic(), nil
}

// IncrementalTopics returns all incremental topics that this corpus should consume.
func (c Corpus) IncrementalTopics() []string {
	return []string{IncrementalSourceTopic, OnboardSourceTopic}
}

const backfillTopicPrefix = "blackbird.v1.Backfill"

// EpochBackfillTopic returns the name of the per-epoch single backfill topic for this corpus and epoch.
func (c Corpus) EpochBackfillTopic(epochID types.EpochID) string {
	return fmt.Sprintf("%s.%s.%d", backfillTopicPrefix, c.String(), epochID)
}

// NOTE: This uses the cluster (not the corpus) in the topic name.
func (c Corpus) ShardAssignmentTopic() string {
	return fmt.Sprintf("blackbird.v0.%s.ShardAssignment", c.ClusterName())
}

// NOTE: This uses the cluster (not the corpus) in the topic name.
func (c Corpus) ShardAssignmentSnapshotTopic() string {
	return fmt.Sprintf("blackbird.v0.%s.ShardAssignmentSnapshot", c.ClusterName())
}

func (c Corpus) ClusterName() string {
	return clusterNames[c]
}

func (c Corpus) ConsumerGroup(epochID types.EpochID) string {
	return fmt.Sprintf("blackbird-%s-%d", strings.ToLower(c.String()), epochID)
}

func (c Corpus) DefaultEmbeddingModel() (string, int) {
	return Text3SmallInference, 512
}

// Set implements envconfig.Setter interface
func (c *Corpus) Set(value string) error {
	for _, corpus := range Corpora {
		if corpus.String() == value {
			*c = corpus
			return nil
		}
	}

	return errors.Errorf("unknown corpus %s", value)
}

func IsBackfillTopic(topic string) bool {
	return strings.HasPrefix(topic, backfillTopicPrefix)
}

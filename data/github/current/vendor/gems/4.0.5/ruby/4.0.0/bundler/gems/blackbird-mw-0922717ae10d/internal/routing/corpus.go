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
	Cyan
	Magenta
	Brown
)

var Corpora = []Corpus{Blue, Green, Yellow, Red, Orange, Violet, Cyan, Magenta, Brown}

func (c Corpus) String() string {
	return [...]string{"Blue", "Green", "Yellow", "Red", "Orange", "Violet", "Cyan", "Magenta", "Brown"}[c]
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

func GetOtherCorpora(corpus Corpus, stamp Stamp) []Corpus {
	var corpora []Corpus
	for _, c := range stamp.EnabledCorpora() {
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
	// The incremental topic for external ingest.
	ExternalIncrementalSourceTopic string = "blackbird.v0.external.FilesetChangeEvents"
)

// There is currently a 1:1 mapping between corpus and cluster in our system.
// This might not always be the case, but the following map will suffice for
// now.
var clusterNames = map[Corpus]string{
	Blue:    "zeta",
	Green:   "eta",
	Yellow:  "theta",
	Red:     "iota",
	Orange:  "kappa",
	Violet:  "lambda",
	Cyan:    "mu",
	Magenta: "nu",
	Brown:   "xi",
}

// Names of cache clusters. Cache clusters don't belong to a particular corpus.
var (
	cacheCluster001 = "cache-001"
	cacheCluster002 = "cache-002"
	cacheCluster003 = "cache-003"
	cacheCluster004 = "cache-004"
	cacheCluster005 = "cache-005"
	cacheCluster006 = "cache-006"
)

var CacheClusterNames = []string{cacheCluster001, cacheCluster002, cacheCluster003, cacheCluster004, cacheCluster005, cacheCluster006}

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
		return fmt.Sprintf("blackbird.v0.%s.ShardAssignment", topicSegmentForCacheCluster(cluster)), nil
	}

	corpus, err := CorpusFromCluster(cluster)
	if err != nil {
		return "", err
	}

	return corpus.ShardAssignmentTopic(), nil
}

func ShardAssignmentSnapshotTopicForCluster(cluster string) (string, error) {
	if IsCacheCluster(cluster) {
		return fmt.Sprintf("blackbird.v0.%s.ShardAssignmentSnapshot", topicSegmentForCacheCluster(cluster)), nil
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

// ConsumedTopic returns the fake Kafka topic for reporting consumed offsets. It
// includes a `^` character in it, which is invalid in real Kafka topic names.
func ConsumedTopic(topic string) string {
	return fmt.Sprintf("%s^consumed", topic)
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

// Returns true if topic is a per epoch backfill topic or an external backfill topic.
func IsBackfillTopic(topic string) bool {
	// external backfills use a different prefix. This isn't an exported
	// constant because the Go code doesn't need to know about these topics.
	const externalBackfillTopicPrefix = "blackbird.v1.external.Backfill"

	return !strings.HasSuffix(topic, "^consumed") && (strings.HasPrefix(topic, backfillTopicPrefix) || strings.HasPrefix(topic, externalBackfillTopicPrefix))
}

// Hydro topics cannot have "-" in them, so our `cache-ddd` cluster name needs
// to be turned into `cacheddd` in the topic name.
func topicSegmentForCacheCluster(cluster string) string {
	return strings.ReplaceAll(cluster, "-", "")
}

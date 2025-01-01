package routing

import (
	"testing"

	"github.com/IBM/sarama"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
)

// NOTE: This wraps the Rust calc_shard_id function which is parameterized by
// epoch and partition count. If epoch ID < 305 and partitions == 32, it uses
// the old sharding, equivalent to what blackbird-mw did. Otherwise, it uses new
// sharding.
func Test_PartitionSelection(t *testing.T) {
	const (
		partitions = 32
	)
	ot := DocumentTopic{Partitions: partitions}

	var tests = []struct {
		sha      string
		expected int32
	}{
		{
			sha:      "20ae66842f996b5540b8f0e2aa32881a1eb37ad7",
			expected: 4,
		},
		{
			sha:      "ffffffffffffffffffffffffffffffffffffffff",
			expected: 31,
		},
		{
			sha:      "0000000000000000000000000000000000000000",
			expected: 0,
		},
		{
			sha:      "bdf4ac1088ad6e8e97bb566f3849eeb36aff0050",
			expected: 16,
		},
		{
			sha:      "6f0c70abbb3e606a6f168bcb8d8dbb3033db25b3",
			expected: 11,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.sha, func(t *testing.T) {
			oid, err := gitaccess.NewObjectIDFromSHA(test.sha)
			require.NoError(t, err)

			partition, err := ot.PartitionForSHA(oid)
			require.NoError(t, err)
			require.Equal(t, test.expected, partition, "unexpected partition selected for sha %q in new scheme", test.sha)
		})
	}
}

func Test_PartitionSelectionErrors(t *testing.T) {
	oid, err := gitaccess.NewObjectIDFromSHA("6f0c70abbb3e606a6f168bcb8d8dbb3033db25b3")
	require.NoError(t, err)

	ot := DocumentTopic{}

	_, err = ot.PartitionForSHA(oid)
	require.Error(t, err)
	require.Equal(t, "must be at least one partition", err.Error())
}

func Test_NewDocumentTopicFromTopicDetails(t *testing.T) {
	detail := sarama.TopicDetail{NumPartitions: 1}

	var tests = []struct {
		topic    string
		expected *DocumentTopic
	}{
		{
			topic:    "blackbird.v1.GitDocument.Blue.1",
			expected: &DocumentTopic{Corpus: Blue, EpochID: 1, Partitions: 1},
		},
		{
			topic:    "blackbird.v1.GitDocument.Green.222",
			expected: &DocumentTopic{Corpus: Green, EpochID: 222, Partitions: 1},
		},
		{
			// Not a document topic
			topic:    "blackbird.v1.SnapshotTreeUpdate.Blue.1",
			expected: nil,
		},
		{
			topic:    "blackbird.v1.SnapshotTreeUpdate.Green.222",
			expected: nil,
		},
		{
			// Unknown corpus
			topic:    "blackbird.v1.GitDocument.XYZ.2",
			expected: nil,
		},
		{
			// Wrong format
			topic:    "blackbird.v1.GitDocumentXYZ.2",
			expected: nil,
		},
		{
			// non-epoch topics are ignored
			topic:    "blackbird.v1.GitDocumentBlue",
			expected: nil,
		},
		{
			// v0 topics are ignored
			topic:    "blackbird.v0.GitDocument.Blue.123",
			expected: nil,
		},
		{
			topic:    "blackbird.v1.GitDocument.Blue.asdf",
			expected: nil,
		},
		{
			topic:    "__consumer_offsets",
			expected: nil,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.topic, func(t *testing.T) {
			t.Parallel()

			ot, err := NewDocumentTopicFromTopicDetail(test.topic, detail)

			if test.expected == nil {
				require.Nil(t, ot)
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, test.expected, ot)
			}
		})
	}
}

func Test_NewSnapshotTopicFromTopicDetails(t *testing.T) {
	detail := sarama.TopicDetail{NumPartitions: 1}

	var tests = []struct {
		topic    string
		expected *SnapshotTopic
	}{
		{
			topic:    "blackbird.v1.SnapshotTreeUpdate.Blue.1",
			expected: &SnapshotTopic{Corpus: Blue, EpochID: 1},
		},
		{
			topic:    "blackbird.v1.SnapshotTreeUpdate.Green.222",
			expected: &SnapshotTopic{Corpus: Green, EpochID: 222},
		},
		{
			// Not a snapshot topic
			topic:    "blackbird.v1.GitDocument.Blue.1",
			expected: nil,
		},
		{
			// Not a snapshot topic
			topic:    "blackbird.v1.GitDocument.Green.222",
			expected: nil,
		},
		{
			// Unknown corpus
			topic:    "blackbird.v1.SnapshotTreeUpdate.XYZ.2",
			expected: nil,
		},
		{
			// Wrong format
			topic:    "blackbird.v1.SnapshotTreeUpdateXYZ.2",
			expected: nil,
		},
		{
			// non-epoch topics are ignored
			topic:    "blackbird.v1.SnapshotTreeUpdateBlue",
			expected: nil,
		},
		{
			// v0 topics are ignored
			topic:    "blackbird.v0.SnapshotTreeUpdate.Blue.123",
			expected: nil,
		},
		{
			topic:    "blackbird.v1.SnapshotTreeUpdate.Blue.asdf",
			expected: nil,
		},
		{
			topic:    "__consumer_offsets",
			expected: nil,
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.topic, func(t *testing.T) {
			t.Parallel()

			ot, err := NewSnapshotTopicFromTopicDetail(test.topic, detail)

			if test.expected == nil {
				require.Nil(t, ot)
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				require.Equal(t, test.expected, ot)
			}
		})
	}
}

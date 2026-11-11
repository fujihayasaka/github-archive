package routing

import (
	"testing"

	"github.com/kelseyhightower/envconfig"
	"github.com/stretchr/testify/require"
)

type config struct {
	Corpus Corpus `envconfig:"some_test_field" default:"Blue"`
}

func Test_EnvconfigSetter(t *testing.T) {
	c := &config{}
	err := envconfig.Process("", c)
	require.NoError(t, err)
	require.Equal(t, Blue, c.Corpus)
}

func TestFromString(t *testing.T) {
	c, _ := CorpusFromString("blue")
	require.Equal(t, Blue, c)

	c, _ = CorpusFromString("green")
	require.Equal(t, Green, c)

	c, _ = CorpusFromString("yellow")
	require.Equal(t, Yellow, c)

	c, _ = CorpusFromString("red")
	require.Equal(t, Red, c)

	c, _ = CorpusFromString("orange")
	require.Equal(t, Orange, c)
}

func TestConsumerGroupsAndTopics(t *testing.T) {
	require.Equal(t, "blackbird-blue-460", Blue.ConsumerGroup(460))
	require.Equal(t, "blackbird.v1.Backfill.Blue.123", Blue.EpochBackfillTopic(123))
	require.Equal(t, incrTopics, Blue.IncrementalTopics())

	require.Equal(t, "blackbird-green-200", Green.ConsumerGroup(200))
	require.Equal(t, "blackbird.v1.Backfill.Green.123", Green.EpochBackfillTopic(123))
	require.Equal(t, incrTopics, Green.IncrementalTopics())

	require.Equal(t, "blackbird-yellow-490", Yellow.ConsumerGroup(490))
	require.Equal(t, "blackbird.v1.Backfill.Yellow.123", Yellow.EpochBackfillTopic(123))
	require.Equal(t, incrTopics, Yellow.IncrementalTopics())
}

var incrTopics = []string{IncrementalSourceTopic, OnboardSourceTopic}

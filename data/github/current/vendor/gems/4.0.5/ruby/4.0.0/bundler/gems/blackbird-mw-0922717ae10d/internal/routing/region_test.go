package routing

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestKafkaClusterResolver(t *testing.T) {
	resolverMap := map[string]Region{
		"eta":       DefaultRegion,
		"zeta":      DefaultRegion,
		"kappa":     GCCUS02,
		"lambda":    GCCUS02,
		"cache-001": DefaultRegion,
		"cache-002": GCCUS02,
	}
	defaultBrokers := []string{"broker1", "broker2"}
	gcCus02Brokers := []string{"broker3", "broker4"}

	resolver := NewClusterResolver(map[Region][]string{
		DefaultRegion: defaultBrokers,
		GCCUS02:       gcCus02Brokers,
	}, resolverMap)

	t.Run("AllBrokers", func(t *testing.T) {
		expected := map[Region][]string{
			DefaultRegion: {"broker1", "broker2"},
			GCCUS02:       {"broker3", "broker4"},
		}
		assert.Equal(t, expected, resolver.AllBrokers())
	})

	tests := []struct {
		corpus  Corpus
		region  Region
		brokers []string
	}{
		{
			corpus:  Green,
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
		{
			corpus:  Blue,
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
		{
			corpus:  Orange,
			region:  GCCUS02,
			brokers: []string{"broker3", "broker4"},
		},
		{
			corpus:  Violet,
			region:  GCCUS02,
			brokers: []string{"broker3", "broker4"},
		},
		{
			corpus:  Magenta,
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.corpus.String(), func(t *testing.T) {
			assert.Equal(t, tt.region, resolver.GetRegion(tt.corpus.ClusterName()))
			assert.Equal(t, tt.brokers, resolver.GetBrokers(tt.corpus.ClusterName()))
		})
	}

	cacheTests := []struct {
		cluster string
		region  Region
		brokers []string
	}{
		{
			cluster: "cache-001",
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
		{
			cluster: "cache-002",
			region:  GCCUS02,
			brokers: []string{"broker3", "broker4"},
		},
		{
			cluster: "cache-003",
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
	}

	for _, tt := range cacheTests {
		t.Run(tt.cluster, func(t *testing.T) {
			assert.Equal(t, tt.region, resolver.GetRegion(tt.cluster))
			assert.Equal(t, tt.brokers, resolver.GetBrokers(tt.cluster))
		})
	}
}

func TestNoDefaultKafkaClusterResolver(t *testing.T) {
	resolverMap := map[string]Region{
		"lambda": GCCUS02,
	}
	defaultBrokers := []string{"broker1", "broker2"}
	gcCus02Brokers := []string{"broker3", "broker4"}

	resolver := NewClusterResolver(map[Region][]string{
		DefaultRegion: defaultBrokers,
		GCCUS02:       gcCus02Brokers,
	}, resolverMap)

	t.Run("AllBrokers", func(t *testing.T) {
		expected := map[Region][]string{
			DefaultRegion: {"broker1", "broker2"},
			GCCUS02:       {"broker3", "broker4"},
		}
		assert.Equal(t, expected, resolver.AllBrokers())
	})

	tests := []struct {
		corpus  Corpus
		region  Region
		brokers []string
	}{
		{
			corpus:  Green,
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
		{
			corpus:  Violet,
			region:  GCCUS02,
			brokers: []string{"broker3", "broker4"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.corpus.String(), func(t *testing.T) {
			assert.Equal(t, tt.region, resolver.GetRegion(tt.corpus.ClusterName()))
			assert.Equal(t, tt.brokers, resolver.GetBrokers(tt.corpus.ClusterName()))
		})
	}
}

func TestEmptyKafkaClusterResolver(t *testing.T) {
	resolverMap := map[string]Region{}
	defaultBrokers := []string{"broker1", "broker2"}
	gcCus02Brokers := []string{}

	resolver := NewClusterResolver(map[Region][]string{
		DefaultRegion: defaultBrokers,
		GCCUS02:       gcCus02Brokers,
	}, resolverMap)

	t.Run("AllBrokers", func(t *testing.T) {
		expected := map[Region][]string{
			DefaultRegion: {"broker1", "broker2"},
			GCCUS02:       {},
		}
		assert.Equal(t, expected, resolver.AllBrokers())
	})

	tests := []struct {
		corpus  Corpus
		region  Region
		brokers []string
	}{
		{
			corpus:  Green,
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.corpus.String(), func(t *testing.T) {
			assert.Equal(t, tt.region, resolver.GetRegion(tt.corpus.ClusterName()))
			assert.Equal(t, tt.brokers, resolver.GetBrokers(tt.corpus.ClusterName()))
		})
	}

	cacheTests := []struct {
		cluster string
		region  Region
		brokers []string
	}{
		{
			cluster: "cache-001",
			region:  DefaultRegion,
			brokers: []string{"broker1", "broker2"},
		},
	}

	for _, tt := range cacheTests {
		t.Run(tt.cluster, func(t *testing.T) {
			assert.Equal(t, tt.region, resolver.GetRegion(tt.cluster))
			assert.Equal(t, tt.brokers, resolver.GetBrokers(tt.cluster))
		})
	}
}

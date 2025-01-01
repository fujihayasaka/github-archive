package healthcheck

import (
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/routing"
)

func TestShouldSkipProbe(t *testing.T) {
	t.Run("returns cluster not indexing skip reason if cluster is not indexing", func(t *testing.T) {
		cluster := &ClusterHealthSummary{
			IngestLag:  0, // no indexing lag
			ServingLag: 0, // no serving lag
			Status: &routing.ClusterStatusSummary{
				IsIndexing:    false,
				ServingOffset: 1,
			},
		}

		skipReason := ShouldSkipProbe(cluster)
		require.Equal(t, "cluster is not indexing", skipReason)
	})

	t.Run("returns cluster not indexing skip reason if cluster is not indexing", func(t *testing.T) {
		cluster := &ClusterHealthSummary{
			IngestLag:  0, // no indexing lag
			ServingLag: 0, // no serving lag
			Status: &routing.ClusterStatusSummary{
				IsIndexing:    true,
				ServingOffset: 0, // not serving
			},
		}

		skipReason := ShouldSkipProbe(cluster)
		require.Equal(t, "cluster is not serving", skipReason)
	})

	t.Run("returns serving lag too high skip reason if cluster's serving lag exceeds threshold", func(t *testing.T) {
		cluster := &ClusterHealthSummary{
			IngestLag:  0,                                        // no indexing lag
			ServingLag: servingLagThreshold + 1*time.Millisecond, // just over the threshold
			Status: &routing.ClusterStatusSummary{
				IsIndexing:    true,
				ServingOffset: 1,
			},
		}

		skipReason := ShouldSkipProbe(cluster)
		require.Equal(t, "serving lag is too high", skipReason)
	})

	t.Run("returns ingest lag too high skip reason if cluster's ingest lag exceeds threshold", func(t *testing.T) {
		cluster := &ClusterHealthSummary{
			IngestLag:  ingestLagThreshold + 1*time.Millisecond, // just over the threshold
			ServingLag: 0,                                       // No serving lag
			Status: &routing.ClusterStatusSummary{
				IsIndexing:    true,
				ServingOffset: 1,
			},
		}

		skipReason := ShouldSkipProbe(cluster)
		require.Equal(t, "ingest lag is too high", skipReason)
	})

	t.Run("no skip reasons if all conditions are met", func(t *testing.T) {
		cluster := &ClusterHealthSummary{
			IngestLag:  ingestLagThreshold - 1*time.Millisecond, // right at the threshold of being stale
			ServingLag: servingLagThreshold,
			Status: &routing.ClusterStatusSummary{
				IsIndexing:    true,
				ServingOffset: 1,
			},
		}

		skipReason := ShouldSkipProbe(cluster)
		require.Equal(t, "", skipReason)
	})
}

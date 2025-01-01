package healthcheck

import "time"

// servingLagThreshold is the maximum amount of time a cluster's serving
// timestamp can be behind indicating the index is becoming stale. This can be
// caused by a variety of error conditions, but when this happens, we want to
// prevent adding further stress and load on the cluster's crawlers and not
// publish Onboarding topic messages.
const servingLagThreshold = 15 * time.Minute

// ingestLagThreshold is the maximum amount of time that a cluster can be behind
// for the RepositoryChanged topic before disabling health checks. This is to
// prevent checks from publishing additional Onboarding topic messages and
// adding load on the crawlers.
const ingestLagThreshold = 15 * time.Minute

// ShouldSkipProbe determines if the prober should skip checking repo metadata
// based on various conditions. Returns a string that when not empty is the
// reason why the prober should skip probing, or an error.
func ShouldSkipProbe(cluster *ClusterHealthSummary) string {
	if !cluster.Status.IsIndexing {
		return "cluster is not indexing"
	}

	if cluster.Status.ServingOffset == 0 {
		return "cluster is not serving"
	}

	if cluster.ServingLag > servingLagThreshold {
		return "serving lag is too high"
	}

	if cluster.IngestLag > ingestLagThreshold {
		return "ingest lag is too high"
	}

	return ""
}

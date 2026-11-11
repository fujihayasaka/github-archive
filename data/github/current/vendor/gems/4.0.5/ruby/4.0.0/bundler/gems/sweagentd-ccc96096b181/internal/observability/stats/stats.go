// Package stats provides DataDog statistics client configuration.
package stats

import (
	"time"

	"github.com/github/go-stats"
)

// NewClient generates a new statter for use with DataDog.
func NewClient(
	isDevelopment bool,
	statsPeriod time.Duration,
	statsAddr,
	serviceName,
	environment,
	podName,
	containerName,
	namespace string,
) (stats.Client, error) {
	if isDevelopment {
		// run `nc -u -l -p 28125` to see statsd output
		statsAddr = "localhost:28125"
	}

	if statsAddr == "" {
		return stats.NullStatter, nil
	}

	client := stats.NewClient(stats.UDPSink(statsAddr), statsPeriod, serviceName)

	return client.WithTags(stats.Tags{
		"env":                 environment,
		"deployed_to":         environment, // We are double reporting this because we need to move to only using "deployed_to". See https://github.com/github/observability-delivery/issues/211
		"catalog_service":     serviceName,
		"service":             serviceName,
		"pod_name":            podName,
		"kube_container_name": containerName,
		"kube_namespace":      namespace,
	}), nil
}

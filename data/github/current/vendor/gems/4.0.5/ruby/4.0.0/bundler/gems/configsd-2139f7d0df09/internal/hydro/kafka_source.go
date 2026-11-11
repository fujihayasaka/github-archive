// Package hydro provides interfaces and implementations for consuming messages from Hydro streams.
package hydro

import (
	"fmt"

	"github.com/IBM/sarama"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-server/runtime"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// KafkaSource generates a hydro source with the provided configuration.
func KafkaSource(brokers []string, server *runtime.Server, group, topic string) (hydro.Source, error) {
	kcfg, err := hydro.NewKafkaConfig(brokers,
		hydro.WithKafkaLogger(log.StdLogAdapter(server.Logger.Info)),
		hydro.WithKafkaStats(server.Statter),
		// this is a VERY old version, but it's the only one that works with kafka-lite
		hydro.WithKafkaVersion(sarama.V1_1_1_0.String()),
	)
	if err != nil {
		return nil, fmt.Errorf("creating consumer kafka config: %w", err)
	}

	src, err := hydro.NewKafkaSource(*kcfg, group, []string{topic})
	if err != nil {
		return nil, fmt.Errorf("creating kafka source: %w", err)
	}
	return src, nil
}

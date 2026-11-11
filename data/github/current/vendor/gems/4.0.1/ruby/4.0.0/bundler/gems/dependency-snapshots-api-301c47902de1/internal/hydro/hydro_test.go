package hydro

import (
	"testing"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/require"
)

func TestNewKafkaPublisherConfig(t *testing.T) {
	t.Run("successful config creation", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:     "dsapi-test",
			HydroKafkaBrokers: "localhost:9092",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		kafkaConfig, err := NewKafkaPublisherConfig(cfg, logger, statter)
		require.NoError(t, err)
		require.NotNil(t, kafkaConfig)
	})

	t.Run("missing KafkaClientID", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:     "",
			HydroKafkaBrokers: "localhost:9092",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		_, err := NewKafkaPublisherConfig(cfg, logger, statter)
		require.Error(t, err)
		require.Contains(t, err.Error(), "KafkaClientID must be non-empty")
	})

	t.Run("missing HydroKafkaBrokers", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:     "dsapi-test",
			HydroKafkaBrokers: "",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		_, err := NewKafkaPublisherConfig(cfg, logger, statter)
		require.Error(t, err)
		require.Contains(t, err.Error(), "HydroKafkaBrokers must be non-empty")
	})

	t.Run("TLS port requires cert location", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:        "dsapi-test",
			HydroKafkaBrokers:    "localhost:9093",
			KafkaSSLCertLocation: "",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		_, err := NewKafkaPublisherConfig(cfg, logger, statter)
		require.Error(t, err)
		require.Contains(t, err.Error(), "KAFKA_SSL_CERTIFICATE_LOCATION must be assigned")
	})
}

func TestNewKafkaConsumerConfig(t *testing.T) {
	t.Run("successful config creation", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:      "dsapi-test",
			HydroKafkaBrokers:  "localhost:9092",
			KafkaConsumerGroup: "dsapi-consumers",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		kafkaConfig, err := NewKafkaConsumerConfig(cfg, logger, statter)
		require.NoError(t, err)
		require.NotNil(t, kafkaConfig)
	})

	t.Run("missing KafkaConsumerGroup", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:     "dsapi-test",
			HydroKafkaBrokers: "localhost:9092",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		_, err := NewKafkaConsumerConfig(cfg, logger, statter)
		require.Error(t, err)
		require.Contains(t, err.Error(), "KafkaConsumerGroup must be non-empty for consumers")
	})

	t.Run("valid KafkaInitialOffsets", func(t *testing.T) {
		validOffsets := []string{"newest", "oldest", ""}

		for _, offset := range validOffsets {
			cfg := &config.Config{
				KafkaClientID:       "dsapi-test",
				HydroKafkaBrokers:   "localhost:9092",
				KafkaConsumerGroup:  "dsapi-consumers",
				KafkaInitialOffsets: offset,
			}
			logger := log.NewNullLogger()
			statter := stats.NullStatter

			kafkaConfig, err := NewKafkaConsumerConfig(cfg, logger, statter)

			require.NoError(t, err)
			require.NotNil(t, kafkaConfig)
		}
	})

	t.Run("invalid KafkaInitialOffsets", func(t *testing.T) {
		cfg := &config.Config{
			KafkaClientID:       "dsapi-test",
			HydroKafkaBrokers:   "localhost:9092",
			KafkaConsumerGroup:  "dsapi-consumers",
			KafkaInitialOffsets: "invalid_option",
		}
		logger := log.NewNullLogger()
		statter := stats.NullStatter

		_, err := NewKafkaConsumerConfig(cfg, logger, statter)

		require.Error(t, err)
		require.Contains(t, err.Error(), "invalid Kafka initial offsets config value")
	})
}

func TestNewHydroLogger(t *testing.T) {
	t.Run("with valid logger", func(t *testing.T) {
		logger := log.NewNullLogger()
		hydroLogger := NewHydroLogger(logger)
		require.NotNil(t, hydroLogger)
		require.NotNil(t, hydroLogger.fieldLogger)
	})

	t.Run("with nil logger", func(t *testing.T) {
		hydroLogger := NewHydroLogger(nil)
		require.NotNil(t, hydroLogger)
		require.NotNil(t, hydroLogger.fieldLogger)
	})

	t.Run("logger methods don't panic", func(t *testing.T) {
		logger := log.NewNullLogger()
		hydroLogger := NewHydroLogger(logger)

		// These should not panic
		require.NotPanics(t, func() {
			hydroLogger.Print("test")
			hydroLogger.Printf("test %s", "formatted")
			hydroLogger.Println("test", "line")
		})
	})
}

func TestBuildMessage(t *testing.T) {
	tests := []struct {
		name     string
		vals     []interface{}
		expected string
	}{
		{
			name:     "single value",
			vals:     []interface{}{"hello"},
			expected: "hello",
		},
		{
			name:     "multiple values",
			vals:     []interface{}{"hello", "world"},
			expected: "hello world",
		},
		{
			name:     "mixed types",
			vals:     []interface{}{"count", 42, "done"},
			expected: "count 42 done",
		},
		{
			name:     "empty",
			vals:     []interface{}{},
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := buildMessage(tt.vals)
			require.Equal(t, tt.expected, result)
		})
	}
}

func TestNewPublisherRejectsEnterprise(t *testing.T) {
	cfg := &config.Config{
		Enterprise:        true,
		KafkaClientID:     "dsapi-test",
		HydroKafkaBrokers: "localhost:9092",
	}
	logger := log.NewNullLogger()
	statter := stats.NullStatter

	_, err := NewPublisher(cfg, logger, statter)
	require.Error(t, err)
	require.Contains(t, err.Error(), "not supported in GHES")
}

func TestNewConsumerRejectsEnterprise(t *testing.T) {
	cfg := &config.Config{
		Enterprise:         true,
		KafkaClientID:      "dsapi-test",
		HydroKafkaBrokers:  "localhost:9092",
		KafkaConsumerGroup: "dsapi-consumers",
	}
	logger := log.NewNullLogger()
	statter := stats.NullStatter

	_, err := NewConsumer(cfg, logger, statter, nil)
	require.Error(t, err)
	require.Contains(t, err.Error(), "not supported in GHES")
}

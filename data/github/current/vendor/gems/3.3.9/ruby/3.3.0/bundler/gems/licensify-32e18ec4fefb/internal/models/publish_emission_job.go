package models

import (
	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// PublishEmissionJob is a job to publish an emission.
type PublishEmissionJob struct {
	CustomerID uint64
	UsageTime  int64
}

// GetLoggerFields returns a list of relevant fields for logging.
func (j *PublishEmissionJob) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Uint64("gh.customer_id", j.CustomerID),
		kvp.Int64("gh.usage_time", j.UsageTime),
	}
}

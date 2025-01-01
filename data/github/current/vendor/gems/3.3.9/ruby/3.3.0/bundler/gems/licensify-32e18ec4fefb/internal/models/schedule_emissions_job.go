package models

import (
	"github.com/github/github-telemetry-go/kvp"
	"go.uber.org/zap/zapcore"
)

// ScheduleEmissionsJob is a job to schedule emissions.
type ScheduleEmissionsJob struct {
	UsageTime int64
}

// GetLoggerFields returns a list of relevant fields for logging.
func (j *ScheduleEmissionsJob) GetLoggerFields() []zapcore.Field {
	return []zapcore.Field{
		kvp.Int64("gh.usage_time", j.UsageTime),
	}
}

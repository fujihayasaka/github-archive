package staffbar

import (
	"context"
	"time"
)

// GormLogger is an interface for a gorm.DB logger.
type GormLogger interface {
	Print(v ...interface{})
}

type wrappedLogger struct {
	logger      GormLogger
	reportQuery func(values ...interface{})
}

// NewGormLogger returns a logger for a gorm.DB that will report queries
// for the given context.
func NewGormLogger(ctx context.Context, logger GormLogger) GormLogger {
	queryReporter := func(values ...interface{}) {
		if values[0] != "sql" {
			return
		}

		if duration, ok := values[2].(time.Duration); ok {
			if query, ok := values[3].(string); ok {
				if results, ok := values[5].(int64); ok {
					QueryReporterFromContext(ctx).Report(query, duration, results)
				}
			}
		}
	}
	return &wrappedLogger{logger: logger, reportQuery: queryReporter}
}

// Print satisfies the internal gorm.logger interface.
func (l *wrappedLogger) Print(values ...interface{}) {
	l.logger.Print(values...)
	l.reportQuery(values...)
}

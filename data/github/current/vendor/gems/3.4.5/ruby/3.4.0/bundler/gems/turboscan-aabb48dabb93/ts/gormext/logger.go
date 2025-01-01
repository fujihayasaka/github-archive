// Package gormext provides a collection of Gorm utility functions.
package gormext

import (
	"fmt"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// GormLogger wraps a log.FieldLogger and logs to it
type GormLogger struct {
	logger log.Logger
}

// NewGormLogger creates a gorm logger that wraps the given log.FieldLogger
func NewGormLogger(logger log.Logger) *GormLogger {
	return &GormLogger{logger: logger}
}

// Print satisfies the internal gorm.logger interface
func (g *GormLogger) Print(values ...interface{}) {
	level := values[0]
	fields := []kvp.Field{}

	switch level {
	case "sql":
		if duration, ok := values[2].(time.Duration); ok {
			fields = append(fields, kvp.Float64("gh.operation.duration", float64(duration)))
		}
		if query, ok := values[3].(string); ok {
			g.logger.Debug(query, fields...)
		}
	case "info":
		if msg, ok := values[1].(string); ok {
			g.logger.Debug(msg)
		}
	default:
		for _, v := range values {
			fields = append(fields, kvp.Any("gh.turboscan.value", v))
		}
		g.logger.Error(fmt.Sprint(values[2:]...), fields...)
	}
}

package http

import (
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// leveledLoggerAdapter implements the LeveledLogger interface from go-retryablehttp so that we can
// use the loggers from github-telemetry-go with it.
//
// Unfortunately go-retryablehttp defines its logger as an interface{} and then does a type
// assertion on runtime to panic on the wrong type of logger.
//
// We discovered it after changing the default logger for go-retryablehttp without and adapter like
// this one...
type leveledLoggerAdapter struct {
	logger log.Logger
}

func (l *leveledLoggerAdapter) Error(msg string, keysAndValues ...interface{}) {
	l.logger.Error(msg, toKVP(keysAndValues)...)
}

func (l *leveledLoggerAdapter) Info(msg string, keysAndValues ...interface{}) {
	l.logger.Info(msg, toKVP(keysAndValues)...)
}

func (l *leveledLoggerAdapter) Debug(msg string, keysAndValues ...interface{}) {
	l.logger.Debug(msg, toKVP(keysAndValues)...)
}

func (l *leveledLoggerAdapter) Warn(msg string, keysAndValues ...interface{}) {
	l.logger.Warn(msg, toKVP(keysAndValues)...)
}

func toKVP(keysAndValues []interface{}) []kvp.Field {
	fields := []kvp.Field{}
	length := len(keysAndValues)

	for idx, v := range keysAndValues {
		if idx%2 != 0 {
			continue
		}

		// If the amount of keys and values is odd, we assume the last value is a key and add an empty
		// value for it.
		if key, ok := v.(string); ok {
			if idx+1 == length {
				fields = append(fields, kvp.Any(key, ""))
			} else {
				fields = append(fields, kvp.Any(key, keysAndValues[idx+1]))
			}
		}
	}

	return fields
}

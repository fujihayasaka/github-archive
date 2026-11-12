package log

import (
	"log"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
)

// Func represents "github.com/github/github-telemetry-go/log" methods
type Func func(msg string, fields ...kvp.Field)

// StdLogAdapter creates a log.Logger (stdlib)
func StdLogAdapter(logFunc Func) *log.Logger {
	return log.New(logFunc, "", 0)
}

func (logFunc Func) Write(data []byte) (int, error) {
	logFunc(strings.TrimSpace(string(data)))
	return len(data), nil
}

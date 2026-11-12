package hydro

import (
	"context"
	"fmt"

	"github.com/github/feature-management-client-go/vexi/v2/internal"
)

// Logger is a bridge between the hydro logger and the telemetry logger.
type Logger struct {
	telemetry internal.Telemetry
	ctx       context.Context
}

// NewLogger creates a hydro logger bridge for telemetry.
func NewLogger(ctx context.Context, t internal.Telemetry) *Logger {
	return &Logger{
		telemetry: t,
		ctx:       ctx,
	}
}

// Print routes print log messages to telemetry.
func (ml *Logger) Print(v ...interface{}) {
	ml.telemetry.LogInfo(ml.ctx, fmt.Sprint(v...))
}

// Printf routes printf log messages to telemetry.
func (ml *Logger) Printf(format string, v ...interface{}) {
	ml.telemetry.LogInfo(ml.ctx, fmt.Sprintf(format, v...)) //nolint:staticcheck // The hydro logger interface still needs this.
}

// Println routes println log messages to telemetry.
func (ml *Logger) Println(v ...interface{}) {
	ml.telemetry.LogInfo(ml.ctx, fmt.Sprint(v...))
}

// Panic routes panic log messages to telemetry.
func (ml *Logger) Panic(v ...interface{}) {
	ml.telemetry.LogError(ml.ctx, fmt.Sprint(v...))
}

// Panicf routes panicf log messages to telemetry.
func (ml *Logger) Panicf(format string, v ...interface{}) {
	ml.telemetry.LogError(ml.ctx, fmt.Sprintf(format, v...)) //nolint:staticcheck // The hydro logger interface still needs this.
}

// Panicln routes panicln log messages to telemetry.
func (ml *Logger) Panicln(v ...interface{}) {
	ml.telemetry.LogError(ml.ctx, fmt.Sprint(v...))
}

// Fatal routes fatal log messages to telemetry.
func (ml *Logger) Fatal(v ...interface{}) {
	ml.telemetry.LogError(ml.ctx, fmt.Sprint(v...))
}

// Fatalf routes falalf log messages to telemetry.
func (ml *Logger) Fatalf(format string, v ...interface{}) {
	ml.telemetry.LogError(ml.ctx, fmt.Sprintf(format, v...)) //nolint:staticcheck // The hydro logger interface still needs this.
}

// Fatalln routes fatalln log messages to telemetry.
func (ml *Logger) Fatalln(v ...interface{}) {
	ml.telemetry.LogError(ml.ctx, fmt.Sprint(v...))
}

package config

import (
	"fmt"
	"os"

	"github.com/github/github-telemetry-go/log"
)

// HydroLogger adapts github-telemetry-go log.Logger to the Hydro/Sarama logger interface.
type HydroLogger struct{ l log.Logger }

// NewHydroLogger creates a new Hydro logger adapter.
func NewHydroLogger(logger log.Logger) *HydroLogger {
	return &HydroLogger{l: logger}
}

// Print logs a message at info level.
func (w *HydroLogger) Print(v ...any) { w.l.Info(fmt.Sprint(v...)) }

// Printf logs a formatted message at info level.
func (w *HydroLogger) Printf(format string, v ...any) { w.l.Info(fmt.Sprintf(format, v...)) }

// Println logs a message with a newline at info level.
func (w *HydroLogger) Println(v ...any) { w.l.Info(fmt.Sprintln(v...)) }

// Panic logs a message at error level and panics.
func (w *HydroLogger) Panic(v ...any) { msg := fmt.Sprint(v...); w.l.Error(msg); panic(msg) }

// Panicf logs a formatted message at error level and panics.
func (w *HydroLogger) Panicf(format string, v ...any) {
	msg := fmt.Sprintf(format, v...)
	w.l.Error(msg)
	panic(msg)
}

// Panicln logs a message with a newline at error level and panics.
func (w *HydroLogger) Panicln(v ...any) {
	msg := fmt.Sprintln(v...)
	w.l.Error(msg)
	panic(msg)
}

// Fatal logs a message at error level and exits the program.
func (w *HydroLogger) Fatal(v ...any) {
	msg := fmt.Sprint(v...)
	w.l.Error(msg)
	os.Exit(1) //nolint:revive // deep-exit: fatal
}

// Fatalf logs a formatted message at error level and exits the program.
func (w *HydroLogger) Fatalf(format string, v ...any) {
	msg := fmt.Sprintf(format, v...)
	w.l.Error(msg)
	os.Exit(1) //nolint:revive // deep-exit: fatalf
}

// Fatalln logs a message with a newline at error level and exits the program.
func (w *HydroLogger) Fatalln(v ...any) {
	msg := fmt.Sprintln(v...)
	w.l.Error(msg)
	os.Exit(1) //nolint:revive // deep-exit: fatalln
}

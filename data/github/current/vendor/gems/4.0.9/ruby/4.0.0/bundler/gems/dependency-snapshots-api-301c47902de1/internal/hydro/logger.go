package hydro

import (
	"fmt"

	"github.com/github/github-telemetry-go/log"
)

// hydroLogWrapper wraps our logger to satisfy hydro.Logger interface
type hydroLogWrapper struct {
	fieldLogger log.Logger
}

// NewHydroLogger returns a wrapped instance of our logger suitable for passing to Hydro.
// If the logger is nil, a no-op logger is returned.
func NewHydroLogger(logger log.Logger) *hydroLogWrapper {
	if logger == nil {
		return &hydroLogWrapper{log.NewNullLogger()}
	}
	return &hydroLogWrapper{logger}
}

func (w *hydroLogWrapper) Print(vals ...interface{}) {
	msg := buildMessage(vals)
	w.fieldLogger.Info(msg)
}

func (w *hydroLogWrapper) Printf(format string, vals ...interface{}) {
	msg := fmt.Sprintf(format, vals...)
	w.fieldLogger.Info(msg)
}

func (w *hydroLogWrapper) Println(vals ...interface{}) {
	msg := buildMessage(vals) + "\n"
	w.fieldLogger.Info(msg)
}

func (w *hydroLogWrapper) Panic(vals ...interface{}) {
	msg := buildMessage(vals)
	w.fieldLogger.Error(msg)
	panic(msg)
}

func (w *hydroLogWrapper) Panicf(format string, vals ...interface{}) {
	msg := fmt.Sprintf(format, vals...)
	w.fieldLogger.Error(msg)
	panic(msg)
}

func (w *hydroLogWrapper) Panicln(vals ...interface{}) {
	msg := buildMessage(vals) + "\n"
	w.fieldLogger.Error(msg)
	panic(msg)
}

func (w *hydroLogWrapper) Fatal(vals ...interface{}) {
	msg := buildMessage(vals)
	w.fieldLogger.Error(msg)
	panic(msg)
}

func (w *hydroLogWrapper) Fatalf(format string, vals ...interface{}) {
	msg := fmt.Sprintf(format, vals...)
	w.fieldLogger.Error(msg)
	panic(msg)
}

func (w *hydroLogWrapper) Fatalln(vals ...interface{}) {
	msg := buildMessage(vals) + "\n"
	w.fieldLogger.Error(msg)
	panic(msg)
}

func buildMessage(vals []interface{}) string {
	msg := ""
	for i, val := range vals {
		if i > 0 {
			msg += " "
		}
		msg += fmt.Sprint(val)
	}
	return msg
}

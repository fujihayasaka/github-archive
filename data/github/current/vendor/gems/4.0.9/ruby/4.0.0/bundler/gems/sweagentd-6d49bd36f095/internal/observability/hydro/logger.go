package hydro

import (
	"fmt"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// HydroLogger is a dedicated logger that wraps our normal logger. Used in development
// to provide useful output when publishing/consuming Hydro events.
//
//nolint:revive // HydroLogger name is intentional to match the interface it implements
type HydroLogger struct {
	logger log.Logger
}

var _ hydro.Logger = (*HydroLogger)(nil)

// NewHydroLogger creates a new logger that implements the hydro.Logger interface.
func NewHydroLogger(logger log.Logger) *HydroLogger {
	return &HydroLogger{logger: logger}
}

// Print is the HydroLogger implementation of the Print method.
func (hl *HydroLogger) Print(args ...any) {
	hl.logger.Info(fmt.Sprint(args...))
}

// Printf is the HydroLogger implementation of the Printf method.
func (hl *HydroLogger) Printf(format string, args ...any) {
	hl.logger.Info(fmt.Sprintf(format, args...))
}

// Println is the HydroLogger implementation of the Println method.
func (hl *HydroLogger) Println(args ...any) {
	hl.logger.Info(fmt.Sprint(args...))
}

// Panic is the HydroLogger implementation of the Panic method.
func (hl *HydroLogger) Panic(args ...any) {
	hl.logger.Info(fmt.Sprint(args...))
	panic("hydro panic")
}

// Panicf is the HydroLogger implementation of the Panicf method.
func (hl *HydroLogger) Panicf(format string, args ...any) {
	hl.logger.Info(fmt.Sprintf(format, args...))
	panic("hydro panic")
}

// Panicln is the HydroLogger implementation of the Panicln method.
func (hl *HydroLogger) Panicln(args ...any) {
	hl.logger.Info(fmt.Sprint(args...))
	panic("hydro panic")
}

// Fatal is the HydroLogger implementation of the Fatal method.
func (hl *HydroLogger) Fatal(args ...any) {
	hl.logger.Info(fmt.Sprint(args...))
	panic("hydro fatal")
}

// Fatalf is the HydroLogger implementation of the Fatalf method.
func (hl *HydroLogger) Fatalf(format string, args ...any) {
	hl.logger.Info(fmt.Sprintf(format, args...))
	panic("hydro fatal")
}

// Fatalln is the HydroLogger implementation of the Fatalln method.
func (hl *HydroLogger) Fatalln(args ...any) {
	hl.logger.Info(fmt.Sprint(args...))
	panic("hydro fatal")
}

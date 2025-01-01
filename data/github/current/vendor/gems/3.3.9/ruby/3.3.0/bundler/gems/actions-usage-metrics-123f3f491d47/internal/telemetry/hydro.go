package telemetry

import (
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

type HydroLogger struct {
	print func(string, ...kvp.Field)
	panic func(string, ...kvp.Field)
	fatal func(string, ...kvp.Field)
}

func NewHydroLogger(logger *Logger) hydro.Logger {
	s := HydroLogger{
		print: logger.Info,
		panic: logger.Error,
		fatal: logger.Fatal,
	}
	return &s
}

func (l *HydroLogger) Print(v ...interface{}) {
	l.print(fmt.Sprint(v...))
}

func (l *HydroLogger) Printf(format string, v ...interface{}) {
	l.print(fmt.Sprintf(format, v...))
}

func (l *HydroLogger) Println(v ...interface{}) {
	l.print(fmt.Sprintln(v...))
}

func (l *HydroLogger) Panic(v ...interface{}) {
	l.panic(fmt.Sprint(v...))
}

func (l *HydroLogger) Panicf(format string, v ...interface{}) {
	l.panic(fmt.Sprintf(format, v...))
}

func (l *HydroLogger) Panicln(v ...interface{}) {
	l.panic(fmt.Sprintln(v...))
}

func (l *HydroLogger) Fatal(v ...interface{}) {
	l.fatal(fmt.Sprint(v...))
}

func (l *HydroLogger) Fatalf(format string, v ...interface{}) {
	l.fatal(fmt.Sprintf(format, v...))
}

func (l *HydroLogger) Fatalln(v ...interface{}) {
	l.fatal(fmt.Sprintln(v...))
}

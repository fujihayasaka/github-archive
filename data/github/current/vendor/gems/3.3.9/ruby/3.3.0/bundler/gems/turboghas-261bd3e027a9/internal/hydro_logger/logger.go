// Package hydro_logger contains a wrapper to use a github-telemetry-go logger with hydro.
package hydro_logger

import (
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

var _ hydro.Logger = (*Logger)(nil)

type Logger struct {
	logger log.Logger
}

func New(logger log.Logger) *Logger {
	return &Logger{logger}
}

func (l *Logger) log(formatted string) {
	l.logger.Info(strings.TrimRight(formatted, "\n"), kvp.Bool("gh.kafka", true))
}

func (l *Logger) Print(v ...interface{}) {
	l.log(fmt.Sprint(v...))
}

func (l *Logger) Printf(s string, v ...interface{}) {
	l.log(fmt.Sprintf(s, v...))
}

func (l *Logger) Println(v ...interface{}) {
	l.log(fmt.Sprint(v...))
}

func (l *Logger) Panic(v ...interface{}) {
	panic(v)

}
func (l *Logger) Panicf(s string, v ...interface{}) {
	panic(fmt.Sprintf(s, v...))
}
func (l *Logger) Panicln(v ...interface{}) {
	panic(v)
}

func (l *Logger) Fatal(v ...interface{}) {
	panic(v)
}
func (l *Logger) Fatalf(s string, v ...interface{}) {
	panic(fmt.Sprintf(s, v...))
}
func (l *Logger) Fatalln(v ...interface{}) {
	panic(v)
}

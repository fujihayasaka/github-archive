// Package hydrologger provides a github/go-log logger wrapper that adds hydro-related key-value pairs to the output.
package hydrologger

import (
	"fmt"
	"strings"

	"github.com/github/hydro-client-go/v7/pkg/hydro"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

var _ hydro.Logger = (*Logger)(nil)

type Logger struct {
	logger log.Logger
}

func New(logger log.Logger) *Logger {
	return &Logger{logger}
}

func (l *Logger) log(formatted string) {
	l.logger.Info(strings.TrimRight(formatted, "\n"), kvp.Bool("gh.turboscan.kafka", true))
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
	// NOT USED, TO BE REMOVED
	panic(v)

}
func (l *Logger) Panicf(s string, v ...interface{}) {
	// NOT USED, TO BE REMOVED
	panic(fmt.Sprintf(s, v...))

}
func (l *Logger) Panicln(v ...interface{}) {
	// NOT USED, TO BE REMOVED
	panic(v)
}

func (l *Logger) Fatal(v ...interface{}) {
	// NOT USED, TO BE REMOVED
	panic(v)
}
func (l *Logger) Fatalf(s string, v ...interface{}) {
	// NOT USED, TO BE REMOVED
	panic(fmt.Sprintf(s, v...))

}
func (l *Logger) Fatalln(v ...interface{}) {
	// NOT USED, TO BE REMOVED
	panic(v)
}

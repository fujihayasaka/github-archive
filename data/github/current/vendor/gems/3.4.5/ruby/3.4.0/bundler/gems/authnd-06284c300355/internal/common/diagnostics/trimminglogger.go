package diagnostics

import (
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
)

// A trimmingLogger is a wrapper that removes leading and trailing whitespace from the log messages
//
// This allows loggers that write newlines into their messages (like the Kafka logger) to
// work well with other loggers
type trimmingLogger struct {
	innerLogger log.Logger
}

// Wrap wraps a StandardLogger in an adaptor that trims leading and trailing whitespace.
func TrimmingLogger(innerLogger log.Logger) hydro.Logger {
	return &trimmingLogger{
		innerLogger: innerLogger,
	}
}

// Print calls the underlying logger to print the message
// Arguments are handled in the manner of fmt.Print.
func (l *trimmingLogger) Print(args ...interface{}) {
	msg := strings.TrimSpace(fmt.Sprint(args...))
	l.innerLogger.Info(msg)
}

// Printf calls the underlying logger to print the message
// Arguments are handled in the manner of fmt.Printf.
func (l *trimmingLogger) Printf(format string, args ...interface{}) {
	msg := strings.TrimSpace(fmt.Sprintf(format, args...))
	l.innerLogger.Info(msg)
}

// Println calls the underlying logger to print the message
// Arguments are handled in the manner of fmt.Println.
func (l *trimmingLogger) Println(args ...interface{}) {
	l.Print(args...)
}

// Panic is equivalent to l.Print() followed by a call to panic().
func (l *trimmingLogger) Panic(args ...interface{}) {
	msg := strings.TrimSpace(fmt.Sprint(args...))
	l.innerLogger.Fatal(msg)
}

// Panicf is equivalent to l.Printf() followed by a call to panic().
func (l *trimmingLogger) Panicf(format string, args ...interface{}) {
	msg := strings.TrimSpace(fmt.Sprintf(format, args...))
	l.innerLogger.Fatal(msg)
}

// Panicln is equivalent to l.Println() followed by a call to panic().
func (l *trimmingLogger) Panicln(args ...interface{}) {
	l.Panic(args...)
}

// Fatal is equivalent to l.Print() followed by a call to os.Exit(1).
func (l *trimmingLogger) Fatal(args ...interface{}) {
	msg := strings.TrimSpace(fmt.Sprint(args...))
	l.innerLogger.Fatal(msg)
}

// Fatalf is equivalent to l.Printf() followed by a call to os.Exit(1).
func (l *trimmingLogger) Fatalf(format string, args ...interface{}) {
	msg := strings.TrimSpace(fmt.Sprintf(format, args...))
	l.innerLogger.Fatal(msg)
}

// Fatalln is equivalent to l.Println() followed by a call to os.Exit(1).
func (l *trimmingLogger) Fatalln(args ...interface{}) {
	l.Fatal(args...)
}

package hydro

import (
	"context"
	"errors"
)

// ErrorPanic is used to indicate that a panic was encountered. If it's useful
// to have different behaviour for panics and normal errors then an
// implementation of ErrorReporter.Report can check if the given error wraps
// ErrorPanic using errors.Is.
var ErrorPanic = errors.New("panic handling message batch")

// ErrorReporter is an interface to be used to report unexpected errors or
// panics. It is designed to be satisfied by Reporter from github/go-exceptions.
type ErrorReporter interface {
	Report(context.Context, error, map[string]string) error
}

type LogErrorReporter struct {
	Logger Logger
}

func (ler *LogErrorReporter) Report(_ context.Context, err error, m map[string]string) error {
	ler.Logger.Printf("%v %v", err, m)
	return nil
}

type nilErrorReporterStruct struct{}

func (r *nilErrorReporterStruct) Report(_ context.Context, _ error, _ map[string]string) error {
	return nil
}

var nilErrorReporter = &nilErrorReporterStruct{}

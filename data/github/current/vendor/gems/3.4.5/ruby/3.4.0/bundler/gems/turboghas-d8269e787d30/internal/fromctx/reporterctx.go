package fromctx

import (
	"context"
	"fmt"
	"time"

	"github.com/github/go-exceptions"
	"github.com/github/turboghas/internal/fields"
	"github.com/simon-engledew/ctxkey"
)

type exceptionReporterKey struct {
	ctxkey.ContextKey[ReportException]
}

var ExceptionReporter = exceptionReporterKey{
	ctxkey.New[ReportException](exceptions.NullReporter),
}

type ReportException interface {
	Report(ctx context.Context, exception error, payload map[string]string) error
}

var _ ReportException = &exceptions.Reporter{}

func (e exceptionReporterKey) Report(ctx context.Context, err error, payload map[string]string) {
	p := ExceptionReporterPayload.Value(ctx)
	if p == nil {
		p = make(map[string]string, len(payload))
	}
	for key, value := range fields.Map(err) {
		p[key] = fmt.Sprint(value)
	}
	for key, value := range payload {
		p[key] = value
	}
	// ctx may be cancelled if the program has been terminated
	// this will give the reporter a short amount of time to report the error, otherwise it will give up
	reportCtx, cancelFunc := context.WithDeadline(context.Background(), time.Now().Add(10*time.Second))
	defer cancelFunc()
	reportErr := e.Value(ctx).Report(reportCtx, err, p)
	if reportErr != nil {
		Logger.Value(ctx).WithError(reportErr).Error("Could not report error.")
	}
}

var ExceptionReporterPayload = ctxkey.New[map[string]string](nil)

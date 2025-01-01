package o11y

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-exceptions"
	"github.com/pkg/errors"
	"go.uber.org/zap/zapcore"
)

type errorWithFields struct {
	error
	fields []kvp.Field
}

func (e *errorWithFields) Unwrap() error {
	return e.error
}

func AnnotateError(err error, fields ...kvp.Field) error {
	if err == nil || len(fields) == 0 {
		return err
	}
	return &errorWithFields{error: err, fields: fields}
}

func ErrorToFields(err error) (out []kvp.Field) {
	var target *errorWithFields
	for errors.As(err, &target) {
		out = append(out, target.fields...)
		err = target.Unwrap()
	}
	return
}

func ErrorToFieldsMap(err error) map[string]any {
	enc := zapcore.NewMapObjectEncoder()
	for _, f := range ErrorToFields(err) {
		f.AddTo(enc)
	}
	return enc.Fields
}

type AnnotatingExceptionReporter struct {
	inner ExceptionReporter
}

func (r AnnotatingExceptionReporter) Report(ctx context.Context, exception error, payload map[string]string) error {
	return r.ReportSensitive(ctx, exception, payload, nil)
}

func (r AnnotatingExceptionReporter) ReportSensitive(ctx context.Context, exception error, payload, sensitivePayload map[string]string) error {
	newPayload := map[string]string{}
	for k, v := range payload {
		newPayload[k] = v
	}
	for k, v := range ErrorToFieldsMap(exception) {
		newPayload[k] = fmt.Sprint(v)
	}
	return r.inner.ReportSensitive(ctx, exception, newPayload, sensitivePayload)
}

func NewAnnotatingExceptionReporter(inner *exceptions.Reporter) *AnnotatingExceptionReporter {
	return &AnnotatingExceptionReporter{inner: inner}
}

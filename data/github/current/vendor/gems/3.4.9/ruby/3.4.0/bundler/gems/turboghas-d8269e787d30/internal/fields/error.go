// Package fields allows the caller to annotate an error with kvp Fields.
package fields

import (
	"github.com/github/github-telemetry-go/kvp"
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

func Error(err error, fields ...kvp.Field) error {
	if err == nil || len(fields) == 0 {
		return err
	}
	return &errorWithFields{error: err, fields: fields}
}

func From(err error) (out []kvp.Field) {
	var target *errorWithFields
	for errors.As(err, &target) {
		out = append(out, target.fields...)
		err = target.Unwrap()
	}
	return
}

func Map(err error) map[string]any {
	enc := zapcore.NewMapObjectEncoder()
	for _, f := range From(err) {
		f.AddTo(enc)
	}
	return enc.Fields
}

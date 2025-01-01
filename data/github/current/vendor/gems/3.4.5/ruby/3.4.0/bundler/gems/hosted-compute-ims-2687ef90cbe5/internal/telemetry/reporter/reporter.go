package reporter

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-exceptions"
	"github.com/github/hosted-compute-ims/internal/telemetry/stash"
)

type Reporter struct {
	base *exceptions.Reporter
}

func NewReporter(base *exceptions.Reporter) *Reporter {
	return &Reporter{
		base: base,
	}
}

func (r *Reporter) Report(ctx context.Context, err error, newFields ...kvp.Field) {
	fields := stash.LoggingFieldsFromContext(ctx)
	if len(newFields) > 0 {
		fields = append(fields, newFields...)
	}

	payload := stash.KvpFieldsToMap(fields)

	_ = r.base.Report(ctx, err, payload)
}

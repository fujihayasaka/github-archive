package asql

import (
	"context"
	"strings"
	"text/template"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"

	throttler "github.com/github/go-freno-client"
	"github.com/pkg/errors"
)

// BatchIterator is used for running SQL queries in batches.
type BatchIterator struct {
	Obs         *observability.Observability
	DB          Execer
	DBThrottler throttler.Throttler

	BatchSize int64
	Start     int64
	End       int64
}

type result struct {
	RowsAffected         int64
	SuccessfulIterations int64
}

type templateValues struct {
	Min, Max int64
}

// Run executes a query iteratively in batches between start and end values.
// The query template must interpolate {{.Min}} and {{.Max}} to work correctly.
func (it *BatchIterator) Run(ctx context.Context, queryTemplate string, args ...any) (result, error) {
	var r result

	if it.BatchSize < 1 {
		return r, errors.New("batch size must be greater than 0")
	}

	if it.End < it.Start {
		return r, errors.New("min < max, no iterations will run")
	}

	if !(strings.Contains(queryTemplate, "{{.Min}}") &&
		strings.Contains(queryTemplate, "{{.Max}}")) {
		return r, errors.New("query template does not interpolate Min and Max")
	}

	t, err := template.New("query").Parse(queryTemplate)
	if err != nil {
		return r, err
	}

	kvs := []kvp.Field{
		kvp.Int64("gh.launch.batch_iterator.start", it.Start),
		kvp.Int64("gh.launch.batch_iterator.end", it.End),
	}
	it.Obs.Log(ctx, "starting batch iterator", kvs...)
	for i := it.Start; i <= it.End; i += it.BatchSize {
		query := strings.Builder{}
		templateValues := templateValues{
			Min: i,
			Max: i + it.BatchSize - 1,
		}
		if templateValues.Max > it.End {
			it.Obs.Log(ctx, "clamping max because reached end", append(kvs,
				kvp.Int64("gh.launch.batch_iterator.max", templateValues.Max),
			)...)
			templateValues.Max = it.End
		}
		if templateValues.Min > templateValues.Max {
			return r, nil // nothing to run
		}
		it.Obs.Log(ctx, "running batch", append(kvs,
			kvp.Int64("gh.launch.batch_iterator.min", templateValues.Min),
			kvp.Int64("gh.launch.batch_iterator.max", templateValues.Max),
			kvp.Int64("gh.launch.batch_iterator.cursor", i),
			kvp.Int64("gh.launch.batch_iterator.rows_affected.count", r.RowsAffected),
			kvp.Int64("gh.launch.batch_iterator.batches.count", r.SuccessfulIterations),
		)...)
		err := t.Execute(&query, templateValues)
		if err != nil {
			return r, err
		}

		if err := it.waitForThrottler(ctx); err != nil {
			return r, err
		}

		result, err := it.DB.ExecContext(ctx, query.String(), args...)
		if err != nil {
			return r, err
		}

		rowsAffected, err := result.RowsAffected()
		if err != nil {
			return r, err
		}

		r.RowsAffected += rowsAffected
		r.SuccessfulIterations++
	}

	return r, nil
}

func (it *BatchIterator) waitForThrottler(ctx context.Context) error {
	for {
		canWrite, err := it.DBThrottler.CanWrite(ctx)
		if err != nil {
			return err
		}
		if canWrite {
			return nil
		}

		it.Obs.Log(ctx, "cannot write, waiting on throttler...")
		err = throttler.WaitOnThrottler(ctx, it.DBThrottler)
		if err != nil {
			return err
		}
		it.Obs.Log(ctx, "done waiting on throtttler")
	}
}

// Package experiment contains a helper for the turboscan experiments dashboard at https://app.datadoghq.com/dashboard/3pc-p2c-eh2/turboscan-experiments
package experiment

import (
	"context"
	stderrors "errors" //lint:ignore faillint importing for errors.Join
	"math/rand/v2"
	"strconv"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/google/go-cmp/cmp"
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/appctx"
)

type Options[T any] struct {
	Control                      func() (T, error)
	Candidate                    func() (T, error)
	CompareOptions               cmp.Options
	SkipTests                    bool
	SkipLogMismatch              bool
	SkipReturnErrorInTestingMode bool
}

var ErrMismatch = errors.New("candidate and control did not match")

var isTesting = testing.Testing()

// Do will run the experiment when tryCandidate is true or if we are in the test suite.
// When not in testing it will only ever return the result of control, however it will log and stat any differences
// and the timings.
// During testing it will return an error if the control and candidate do not agree.
func Do[T any](ctx context.Context, name string, tryCandidate bool, opts Options[T]) (zero T, err error) {
	if opts.Control == nil {
		return zero, errors.New("no control function for experiment")
	}

	tryCandidate = tryCandidate || (isTesting && !opts.SkipTests)

	if opts.Candidate == nil || !tryCandidate {
		return opts.Control()
	}

	var controlDuration, candidateDuration time.Duration
	var controlValue, candidateValue T
	var controlErr, candidateErr error

	runners := []func(){
		func() {
			controlStart := time.Now()
			controlValue, controlErr = opts.Control()
			controlDuration = time.Since(controlStart)
		},
		func() {
			candidateStart := time.Now()
			candidateValue, candidateErr = opts.Candidate()
			candidateDuration = time.Since(candidateStart)
		},
	}

	// Shuffle the runs to try to avoid bias from the order in which the control and candidate run.
	rand.Shuffle(len(runners), func(i, j int) {
		runners[i], runners[j] = runners[j], runners[i]
	})

	for _, runner := range runners {
		runner()
	}

	if candidateErr != nil {
		appctx.Logger(ctx).WithError(candidateErr).Error("candidate error", kvp.String("experiment.name", name))
	}

	// We are not checking that the errors are exactly the same, just that they are both nil or both not nil
	errorMatch := (controlErr == nil) == (candidateErr == nil)
	valueMatch := cmp.Equal(controlValue, candidateValue, opts.CompareOptions...)
	match := valueMatch && errorMatch

	statter := appctx.Stats(ctx)
	statter.DistributionMs("experiment.dist.time", stats.Tags{"name": name, "control": "true"}, controlDuration)
	statter.DistributionMs("experiment.dist.time", stats.Tags{"name": name, "control": "false"}, candidateDuration)
	statter.Counter("experiment", stats.Tags{"name": name, "match": strconv.FormatBool(match), "value_match": strconv.FormatBool(valueMatch), "error_match": strconv.FormatBool(errorMatch)}, 1)

	// when running in testing mode return ErrMismatch (and any other errors) so that we can catch experiment
	// differences without having to run the test suite twice.
	if !match && isTesting && !opts.SkipReturnErrorInTestingMode {
		return zero, stderrors.Join(candidateErr, controlErr, ErrMismatch)
	}

	if !match && !opts.SkipLogMismatch {
		diff := cmp.Diff(controlValue, candidateValue, opts.CompareOptions...)
		errorDiff := cmp.Diff(controlErr, candidateErr, opts.CompareOptions...)
		appctx.Logger(ctx).Error("experiment mismatch", kvp.String("experiment.name", name), kvp.String("experiment.diff", diff), kvp.String("experiment.error_diff", errorDiff))
	}

	return controlValue, controlErr
}

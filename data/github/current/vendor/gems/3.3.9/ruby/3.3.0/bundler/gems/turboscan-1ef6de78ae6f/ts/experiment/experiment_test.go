package experiment_test

import (
	"context"
	"testing"

	"github.com/github/go-stats"
	"github.com/google/go-cmp/cmp"
	"github.com/google/go-cmp/cmp/cmpopts"
	"github.com/pkg/errors"
	"go.uber.org/mock/gomock"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mocks"

	"github.com/github/turboscan/ts/experiment"
)

func TestRun(t *testing.T) {
	v, err := experiment.Do(context.Background(), "test_experiment", false, experiment.Options[bool]{
		Candidate: func() (bool, error) {
			return true, nil
		},
		Control: func() (bool, error) {
			return false, nil
		},
		CompareOptions: cmp.Options{cmpopts.EquateEmpty(), cmpopts.SortSlices(func(a, b ts.AnalysisID) bool {
			return a < b
		})},
	})
	// prove the experiment ran due to testing mode, even though tryCandidate was false
	require.ErrorIs(t, err, experiment.ErrMismatch)
	require.False(t, v)
}

func TestDo_ReturnsTheControlError(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	statter := mocks.NewMockStatsClient(mockCtrl)
	ctx := appctx.WithStats(context.Background(), statter)

	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "true"}, gomock.Any())
	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "false"}, gomock.Any())
	statter.EXPECT().Counter("experiment", stats.Tags{"name": "test_experiment", "match": "false", "value_match": "true", "error_match": "false"}, int64(1)).Times(1)

	controlErr := errors.New("control error")

	v, err := experiment.Do(ctx, "test_experiment", true, experiment.Options[bool]{
		Candidate: func() (bool, error) {
			return false, nil
		},
		Control: func() (bool, error) {
			return false, controlErr
		},
		CompareOptions: cmp.Options{cmpopts.EquateEmpty()},
	})
	require.ErrorIs(t, err, controlErr)
	require.False(t, v)
}

func TestDo_DoesNotReturnTheCandidateError(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	statter := mocks.NewMockStatsClient(mockCtrl)
	ctx := appctx.WithStats(context.Background(), statter)

	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "true"}, gomock.Any())
	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "false"}, gomock.Any())
	statter.EXPECT().Counter("experiment", stats.Tags{"name": "test_experiment", "match": "false", "value_match": "true", "error_match": "false"}, int64(1)).Times(1)

	candidateErr := errors.New("candidate error")

	v, err := experiment.Do(ctx, "test_experiment", true, experiment.Options[bool]{
		Candidate: func() (bool, error) {
			return false, candidateErr
		},
		Control: func() (bool, error) {
			return false, nil
		},
		CompareOptions:               cmp.Options{cmpopts.EquateEmpty()},
		SkipReturnErrorInTestingMode: true,
	})
	require.NoError(t, err)
	require.False(t, v)
}

func TestDo_ReturnsMismatchErrorInTestingMode(t *testing.T) {
	candidateErr := errors.New("candidate error")

	v, err := experiment.Do(context.Background(), "test_experiment", true, experiment.Options[bool]{
		Candidate: func() (bool, error) {
			return false, candidateErr
		},
		Control: func() (bool, error) {
			return false, nil
		},
		CompareOptions: cmp.Options{cmpopts.EquateEmpty()},
	})
	require.ErrorIs(t, err, experiment.ErrMismatch)
	require.False(t, v)
}

func TestDo_BothError(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	statter := mocks.NewMockStatsClient(mockCtrl)
	ctx := appctx.WithStats(context.Background(), statter)

	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "true"}, gomock.Any())
	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "false"}, gomock.Any())
	statter.EXPECT().Counter("experiment", stats.Tags{"name": "test_experiment", "match": "true", "value_match": "true", "error_match": "true"}, int64(1)).Times(1)

	candidateErr := errors.New("candidate error")
	controlErr := errors.New("control error")

	v, err := experiment.Do(ctx, "test_experiment", true, experiment.Options[bool]{
		Candidate: func() (bool, error) {
			return false, candidateErr
		},
		Control: func() (bool, error) {
			return false, controlErr
		},
		CompareOptions: cmp.Options{cmpopts.EquateEmpty()},
	})
	require.ErrorIs(t, err, controlErr)
	require.False(t, v)
}

func TestDo_ValuesEqual(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	statter := mocks.NewMockStatsClient(mockCtrl)
	ctx := appctx.WithStats(context.Background(), statter)

	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "true"}, gomock.Any())
	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "false"}, gomock.Any())
	statter.EXPECT().Counter("experiment", stats.Tags{"name": "test_experiment", "match": "true", "value_match": "true", "error_match": "true"}, int64(1)).Times(1)

	v, err := experiment.Do(ctx, "test_experiment", true, experiment.Options[int64]{
		Candidate: func() (int64, error) {
			return 78, nil
		},
		Control: func() (int64, error) {
			return 78, nil
		},
		CompareOptions: cmp.Options{cmpopts.EquateEmpty()},
	})
	require.NoError(t, err)
	require.Equal(t, v, int64(78))
}

func TestDo_ValuesNotEqual(t *testing.T) {
	mockCtrl := gomock.NewController(t)
	statter := mocks.NewMockStatsClient(mockCtrl)
	ctx := appctx.WithStats(context.Background(), statter)

	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "true"}, gomock.Any())
	statter.EXPECT().DistributionMs("experiment.dist.time", stats.Tags{"name": "test_experiment", "control": "false"}, gomock.Any())
	statter.EXPECT().Counter("experiment", stats.Tags{"name": "test_experiment", "match": "false", "value_match": "false", "error_match": "true"}, int64(1)).Times(1)

	v, err := experiment.Do(ctx, "test_experiment", true, experiment.Options[int64]{
		Candidate: func() (int64, error) {
			return 78, nil
		},
		Control: func() (int64, error) {
			return 79, nil
		},
		CompareOptions:               cmp.Options{cmpopts.EquateEmpty()},
		SkipReturnErrorInTestingMode: true,
	})
	require.NoError(t, err)
	require.Equal(t, v, int64(79))
}

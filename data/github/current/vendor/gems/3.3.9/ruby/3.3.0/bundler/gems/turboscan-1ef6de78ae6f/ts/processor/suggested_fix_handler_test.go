package processor_test

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/processor"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
)

func TestSuggestedFixesTelemetry(t *testing.T) {
	ctx := context.Background()
	aqueductMock := &aqueduct.AqueductMock{}
	handler := processor.NewSuggestedFixTelemetryHandler(aqueductMock)

	analysis := &ts.Analysis{ID: 2, Ref: []byte("test")}
	fixedAlertNumbers := []uint32{7, 11}

	before := []*ts.PhysicalAlert{
		{
			ID:             1,
			LogicalAlertID: 1,
			LogicalAlert:   &ts.LogicalAlert{Number: 1},
			Analysis:       &ts.Analysis{ID: 1},
		},
		{
			ID:             2,
			LogicalAlertID: 2,
			LogicalAlert:   &ts.LogicalAlert{Number: 2},
		},
	}

	handler.Handle(ctx, before, analysis, fixedAlertNumbers)

	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	job := aqueductMock.EnqueuedJobs()[0]
	sft, ok := job.(*jobs.SuggestedFixTelemetry)
	if !ok {
		t.Fatal("Type assertion(SuggestedFixTelemetry) failed")
	}
	require.Equal(t, ts.AnalysisID(1), sft.BaselineID)
	require.Equal(t, ts.Ref([]byte("test")), sft.Ref)
	require.Equal(t, []uint32{7, 11}, sft.FixedAlertNumbers)
}

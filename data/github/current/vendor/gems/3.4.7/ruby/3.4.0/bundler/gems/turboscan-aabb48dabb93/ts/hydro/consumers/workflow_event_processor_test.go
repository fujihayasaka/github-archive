package consumers

import (
	"testing"

	actionschemas "github.com/github/hydro-schemas-go/hydro/schemas/github/actions/v0"
	hydroentities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/stretchr/testify/require"
)

// processTestMessage executes the processor on the given message
// and returns the slice of jobs that have been enqueued
func processTestMessage(t *testing.T, wfe *actionschemas.WorkflowExecution) []aqueduct.EnqueableJob {
	t.Helper()

	aqueduct := &aqueduct.AqueductMock{}

	p := &WorkflowEventProcessor{
		aqueduct: aqueduct,
	}

	requireProcessEnvelope(t, p, wfe, topics.WorkflowExecution)

	return aqueduct.EnqueuedJobs()
}

func TestNonCSMessage_WorkflowExecution(t *testing.T) {
	jobs := processTestMessage(t, &actionschemas.WorkflowExecution{
		WorkflowFilePath:     ".github/no_code_scanning.yml",
		CheckSuiteConclusion: hydroentities.CheckSuiteConclusion_SUCCESS,
	})
	require.Zero(t, len(jobs))
}

func TestSkipMessage_ComputeUsage(t *testing.T) {
	// Incorrect workflow file path
	jobs := processComputeUsageTestMessage(t, &actionschemas.ComputeUsage{
		WorkflowFilePath:   []byte(".github/no_code_scanning.yml"),
		CheckRunConclusion: actionschemas.ComputeUsage_RESULT_SUCCESS,
	})
	require.Zero(t, len(jobs))

	// Incorrect job name
	jobs = processComputeUsageTestMessage(t, &actionschemas.ComputeUsage{
		WorkflowFilePath:   []byte(ts.ManagedAnalysisWorkflowPath),
		JobName:            []byte("Random"),
		CheckRunConclusion: actionschemas.ComputeUsage_RESULT_SUCCESS,
	})
	require.Zero(t, len(jobs))
}

func TestConclusion_WorkflowExecution(t *testing.T) {
	cases := map[hydroentities.CheckSuiteConclusion]ts.CodeqlRunStatus{
		hydroentities.CheckSuiteConclusion_UNKNOWN:         ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_NEUTRAL:         ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_SUCCESS:         ts.CodeqlRunStatus_COMPLETED,
		hydroentities.CheckSuiteConclusion_FAILURE:         ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_CANCELLED:       ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_ACTION_REQUIRED: ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_TIMED_OUT:       ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_SKIPPED:         ts.CodeqlRunStatus_FAILED,
		hydroentities.CheckSuiteConclusion_STALE:           ts.CodeqlRunStatus_FAILED,
	}

	for cscValue := range hydroentities.CheckSuiteConclusion_name {
		csc := hydroentities.CheckSuiteConclusion(cscValue)

		// Ensure this case is covered in our cases map
		_, ok := cases[csc]
		require.True(t, ok)

		msg := processTestMessage(t, &actionschemas.WorkflowExecution{
			WorkflowFilePath:     ts.ManagedAnalysisWorkflowPath,
			CheckSuiteConclusion: csc,
		})
		require.Equal(t, 1, len(msg))
		require.Equal(t, cases[csc], msg[0].(jobs.SetDynamicRunConclusion).Conclusion)
	}

}

func TestConclusion_ComputeUsage(t *testing.T) {
	cases := map[actionschemas.ComputeUsage_Conclusion]ts.CodeqlRunStatus{
		actionschemas.ComputeUsage_RESULT_SKIPPED:             ts.CodeqlRunStatus_COMPLETED,
		actionschemas.ComputeUsage_RESULT_SUCCESS:             ts.CodeqlRunStatus_COMPLETED,
		actionschemas.ComputeUsage_RESULT_UNKNOWN:             ts.CodeqlRunStatus_FAILED,
		actionschemas.ComputeUsage_RESULT_FAILURE:             ts.CodeqlRunStatus_FAILED,
		actionschemas.ComputeUsage_RESULT_PARTIALLY_SUCCEEDED: ts.CodeqlRunStatus_FAILED,
		actionschemas.ComputeUsage_RESULT_CANCELLED:           ts.CodeqlRunStatus_FAILED,
	}

	for name := range actionschemas.ComputeUsage_Conclusion_name {
		c := actionschemas.ComputeUsage_Conclusion(name)

		// Ensure this case is covered in our cases map
		_, ok := cases[c]
		require.True(t, ok)

		msg := processComputeUsageTestMessage(t, &actionschemas.ComputeUsage{
			WorkflowFilePath:   []byte(ts.ManagedAnalysisWorkflowPath),
			JobName:            []byte("Adjust Configuration"),
			CheckRunConclusion: c,
		})
		require.Equal(t, 1, len(msg))
		require.Equal(t, cases[c], msg[0].(jobs.SetDynamicRunConclusion).Conclusion)
	}

}

// processTestMessage executes the processor on the given message
// and returns the slice of jobs that have been enqueued
func processComputeUsageTestMessage(t *testing.T, wfe *actionschemas.ComputeUsage) []aqueduct.EnqueableJob {
	t.Helper()

	aqueduct := &aqueduct.AqueductMock{}

	p := &WorkflowEventProcessor{
		aqueduct: aqueduct,
	}

	requireProcessEnvelope(t, p, wfe, topics.ActionsComputeUsage)

	return aqueduct.EnqueuedJobs()
}

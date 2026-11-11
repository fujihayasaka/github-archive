package agentcallback

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/writer"
	"github.com/github/go-exceptions/stacktracers/pkgerrors"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/store/memory"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/require"
)

func TestHandleErrorSkipReport(t *testing.T) {
	t.Run("skipReport true - error logged but not reported", func(t *testing.T) {
		exceptionStream := new(bytes.Buffer)
		reporter, err := exceptions.NewReporter(
			exceptions.WithApplication("sweagentd"),
			exceptions.WithExporter(writer.NewExporter(exceptionStream)),
			exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		)
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		obsv.Reporter = reporter

		jobStore := memory.NewStore()
		jobMgr := &jobManager{
			obsv:      obsv,
			jobsStore: jobStore,
		}

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequest(http.MethodPost, "/test", http.NoBody)

		// Create test job
		job := &jobs.Job{
			ID:        "test-job-skip-true",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
			ActorID:   1,
		}

		_, err = jobMgr.jobsStore.CreateJob(ctx, job)
		require.NoError(t, err)

		// Create error content with skipReport: true
		errorContent := map[string]any{
			"text":       "Test error message",
			"skipReport": true,
		}
		contentBytes, err := json.Marshal(errorContent)
		require.NoError(t, err)

		update := JobUpdate{
			Content: string(contentBytes),
		}

		// Call handleError
		result, err := jobMgr.handleError(ctx, req, job, update)

		// Verify the result
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, jobs.JobStatusFailed, result.Status)
		require.NotNil(t, result.CompletedAt)

		// Verify error was NOT reported to Sentry (mock reporter)
		require.Empty(t, exceptionStream, "Error should not be reported when skipReport is true")

		// Verify job was updated with error
		updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.NotNil(t, updatedJob.Error)
		require.Equal(t, "Test error message", updatedJob.Error.Message)
	})

	t.Run("skipReport false - error logged and reported", func(t *testing.T) {
		exceptionStream := new(bytes.Buffer)
		reporter, err := exceptions.NewReporter(
			exceptions.WithApplication("sweagentd"),
			exceptions.WithExporter(writer.NewExporter(exceptionStream)),
			exceptions.WithStacktraceFunc(pkgerrors.NewStackTracer()),
		)
		require.NoError(t, err)

		obsv := observability.NewNoopExporters()
		obsv.Reporter = reporter

		jobStore := memory.NewStore()
		jobMgr := &jobManager{
			obsv:      obsv,
			jobsStore: jobStore,
		}

		ctx := addUserToContext(context.Background(), t)
		req := httptest.NewRequest(http.MethodPost, "/test", http.NoBody)

		// Create test job
		job := &jobs.Job{
			ID:        "test-job-skip-false",
			OwnerID:   1,
			RepoID:    2,
			RepoOwner: "owner",
			RepoName:  "repo",
			ActorID:   1,
		}

		_, err = jobMgr.jobsStore.CreateJob(ctx, job)
		require.NoError(t, err)

		// Create error content with skipReport: false
		errorContent := map[string]any{
			"text":       "Test error message with reporting",
			"skipReport": false,
		}
		contentBytes, err := json.Marshal(errorContent)
		require.NoError(t, err)

		update := JobUpdate{
			Content: string(contentBytes),
		}

		// Call handleError
		result, err := jobMgr.handleError(ctx, req, job, update)

		// Verify the result
		require.NoError(t, err)
		require.NotNil(t, result)
		require.Equal(t, jobs.JobStatusFailed, result.Status)

		// Verify error WAS reported to Sentry (mock reporter)
		require.NotEmpty(t, exceptionStream)

		// Verify the reported error is of correct type
		require.Contains(t, exceptionStream.String(), "AgentError")
		require.Contains(t, exceptionStream.String(), "Test error message with reporting")

		// Verify job was updated with error
		updatedJob, err := jobStore.GetJob(ctx, job.OwnerID, job.RepoID, job.ID)
		require.NoError(t, err)
		require.NotNil(t, updatedJob.Error)
		require.Equal(t, "Test error message with reporting", updatedJob.Error.Message)
	})
}

package twirpserver

import (
	"testing"

	"github.com/github/sweagentd/internal/jobs"
	proto "github.com/github/sweagentd/proto/jobs/v1"
	"github.com/stretchr/testify/require"
)

func TestConvertJobStatus(t *testing.T) {
	testCases := []struct {
		jobStatus     jobs.JobStatus
		expectedProto proto.JobStatus
	}{
		{jobs.JobStatusPending, proto.JobStatus_JOB_STATUS_PENDING},
		{jobs.JobStatusQueued, proto.JobStatus_JOB_STATUS_QUEUED},
		{jobs.JobStatusRunning, proto.JobStatus_JOB_STATUS_RUNNING},
		{jobs.JobStatusCompleted, proto.JobStatus_JOB_STATUS_COMPLETED},
		{jobs.JobStatusFailed, proto.JobStatus_JOB_STATUS_FAILED},
		{jobs.JobStatusCancelled, proto.JobStatus_JOB_STATUS_CANCELLED},
		{jobs.JobStatusTimedOut, proto.JobStatus_JOB_STATUS_TIMED_OUT},
		{"unknown", proto.JobStatus_JOB_STATUS_INVALID},
	}

	for _, tc := range testCases {
		t.Run(string(tc.jobStatus), func(t *testing.T) {
			result := convertJobStatus(tc.jobStatus)
			require.Equal(t, tc.expectedProto, result)
		})
	}
}

package eventpublisher_test

import (
	"testing"
	"testing/synctest"
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	dependencygraphv1 "github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/osslicensecompliance/hydroproto/hydro/schemas/github/dependencygraph/v1/entities"
	"github.com/github/osslicensecompliance/internal/eventpublisher/testpublisher"
	"github.com/github/osslicensecompliance/internal/models"
)

// synctestTime is the fixed time returned by time.Now() inside synctest.
var synctestTime = timestamppb.New(time.Date(2000, 1, 1, 0, 0, 0, 0, time.UTC))

func TestPublishLicenseCheckProgress(t *testing.T) {
	tests := []struct {
		name                string
		checkJob            *models.CheckJob
		expectedLogMessage  string
		expectedProtoStatus entities.CheckJobStatus
	}{
		{
			name: "starting",
			checkJob: &models.CheckJob{
				Status:            models.Starting,
				CommitSHA:         "abc123def4567890",
				RepositoryID:      1001,
				ReceivedSnapshots: 0,
				ExpectedSnapshots: 0,
			},
			expectedLogMessage:  "Starting license check...",
			expectedProtoStatus: entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING,
		},
		{
			name: "waiting with progress",
			checkJob: &models.CheckJob{
				Status:            models.Waiting,
				CommitSHA:         "abc123def4567890",
				RepositoryID:      1001,
				ReceivedSnapshots: 3,
				ExpectedSnapshots: 5,
			},
			expectedLogMessage:  "Waiting for dependency snapshots on head (3/5 received)...",
			expectedProtoStatus: entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING,
		},
		{
			name: "running",
			checkJob: &models.CheckJob{
				Status:            models.Running,
				CommitSHA:         "abc123def4567890",
				RepositoryID:      1001,
				ReceivedSnapshots: 5,
				ExpectedSnapshots: 5,
			},
			expectedLogMessage:  "Evaluating dependencies against license policy...",
			expectedProtoStatus: entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				tp := testpublisher.NewTestPublisher(t)

				tp.PublishLicenseCheckProgress(t.Context(), tt.checkJob)

				tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
					&dependencygraphv1.PullRequestLicenseCheckProgressed{
						CommitSha:      tt.checkJob.CommitSHA,
						RepositoryId:   int64(tt.checkJob.RepositoryID),
						CheckJobStatus: tt.expectedProtoStatus,
						LogMessage:     tt.expectedLogMessage,
						ProgressedAt:   synctestTime,
						Title:          nil, // title should not be sent for non-terminal statuses
					})
			})
		})
	}
}

func TestPublishLicenseCheckProgress_WithMissingDetectors(t *testing.T) {
	tests := []struct {
		name               string
		checkJob           *models.CheckJob
		expectedLogMessage string
	}{
		{
			name: "waiting with missing detectors",
			checkJob: &models.CheckJob{
				Status:            models.Waiting,
				CommitSHA:         "abc123def4567890",
				RepositoryID:      1001,
				ReceivedSnapshots: 1,
				ExpectedSnapshots: 3,
				MissingDetectors:  []string{"detector-one", "detector-two"},
			},
			expectedLogMessage: "Waiting for dependency snapshots on head (1/3 received)... Missing snapshots from detectors: detector-one, detector-two.",
		},
		{
			name: "waiting with empty missing detectors keeps base log message",
			checkJob: &models.CheckJob{
				Status:            models.Waiting,
				CommitSHA:         "abc123def4567890",
				RepositoryID:      1001,
				ReceivedSnapshots: 1,
				ExpectedSnapshots: 3,
				MissingDetectors:  []string{},
			},
			expectedLogMessage: "Waiting for dependency snapshots on head (1/3 received)...",
		},
		{
			name: "non-waiting status ignores missing detectors",
			checkJob: &models.CheckJob{
				Status:           models.Starting,
				CommitSHA:        "abc123def4567890",
				RepositoryID:     1001,
				MissingDetectors: []string{"detector-one"},
			},
			expectedLogMessage: "Starting license check...",
		},
	}

	statusToProto := map[models.CheckStatus]entities.CheckJobStatus{
		models.Starting: entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING,
		models.Waiting:  entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING,
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				tp := testpublisher.NewTestPublisher(t)

				tp.PublishLicenseCheckProgress(t.Context(), tt.checkJob)

				tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
					&dependencygraphv1.PullRequestLicenseCheckProgressed{
						CommitSha:      tt.checkJob.CommitSHA,
						RepositoryId:   int64(tt.checkJob.RepositoryID),
						CheckJobStatus: statusToProto[tt.checkJob.Status],
						LogMessage:     tt.expectedLogMessage,
						ProgressedAt:   synctestTime,
						Title:          nil,
					})
			})
		})
	}
}

func TestPublishLicenseCheckResult(t *testing.T) {
	tests := []struct {
		name               string
		checkJob           *models.CheckJob
		alertCount         int
		expectedTitle      string
		expectedLogMessage string
	}{
		{
			name: "pass",
			checkJob: &models.CheckJob{
				Status:       models.Pass,
				CommitSHA:    "abc123def4567890",
				RepositoryID: 1001,
			},
			alertCount:         0,
			expectedTitle:      "No new license compliance alerts in code changed by this pull request",
			expectedLogMessage: "✓ License check passed",
		},
		{
			name: "fail with 1 alert",
			checkJob: &models.CheckJob{
				Status:       models.Fail,
				CommitSHA:    "abc123def4567890",
				RepositoryID: 1001,
			},
			alertCount:         1,
			expectedTitle:      "1 new license compliance alert",
			expectedLogMessage: "✗ License check completed with violations. See the comment from license-compliance-bot on this pull request for details.",
		},
		{
			name: "fail with multiple alerts",
			checkJob: &models.CheckJob{
				Status:       models.Fail,
				CommitSHA:    "abc123def4567890",
				RepositoryID: 1001,
			},
			alertCount:         5,
			expectedTitle:      "5 new license compliance alerts",
			expectedLogMessage: "✗ License check completed with violations. See the comment from license-compliance-bot on this pull request for details.",
		},
		{
			name: "fail with zero alerts (edge case)",
			checkJob: &models.CheckJob{
				Status:       models.Fail,
				CommitSHA:    "abc123def4567890",
				RepositoryID: 1001,
			},
			alertCount:         0,
			expectedTitle:      "License check failed",
			expectedLogMessage: "✗ License check completed with violations. See the comment from license-compliance-bot on this pull request for details.",
		},
	}

	statusToProto := map[models.CheckStatus]entities.CheckJobStatus{
		models.Pass: entities.CheckJobStatus_CHECK_JOB_STATUS_PASS,
		models.Fail: entities.CheckJobStatus_CHECK_JOB_STATUS_FAIL,
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				tp := testpublisher.NewTestPublisher(t)

				tp.PublishLicenseCheckResult(t.Context(), tt.checkJob, tt.alertCount)

				tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
					&dependencygraphv1.PullRequestLicenseCheckProgressed{
						CommitSha:      tt.checkJob.CommitSHA,
						RepositoryId:   int64(tt.checkJob.RepositoryID),
						CheckJobStatus: statusToProto[tt.checkJob.Status],
						LogMessage:     tt.expectedLogMessage,
						ProgressedAt:   synctestTime,
						Title:          &wrapperspb.StringValue{Value: tt.expectedTitle},
					})
			})
		})
	}
}

func TestPublishLicenseCheckPass(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		commitSHA := "abc123def4567890"
		repoID := uint64(1001)

		tp.PublishLicenseCheckPass(t.Context(), commitSHA, repoID)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
			&dependencygraphv1.PullRequestLicenseCheckProgressed{
				CommitSha:      commitSHA,
				RepositoryId:   int64(repoID),
				CheckJobStatus: entities.CheckJobStatus_CHECK_JOB_STATUS_PASS,
				LogMessage:     "✓ License check passed",
				ProgressedAt:   synctestTime,
				Title:          &wrapperspb.StringValue{Value: "No new license compliance alerts in code changed by this pull request"},
			})
	})
}

func TestPublishLicenseCheckError(t *testing.T) {
	synctest.Test(t, func(t *testing.T) {
		tp := testpublisher.NewTestPublisher(t)
		commitSHA := "abc123def4567890"
		repoID := uint64(1001)
		sanitizedError := "An unexpected error occurred."

		tp.PublishLicenseCheckError(t.Context(), commitSHA, repoID, sanitizedError)

		tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
			&dependencygraphv1.PullRequestLicenseCheckProgressed{
				CommitSha:      commitSHA,
				RepositoryId:   int64(repoID),
				CheckJobStatus: entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR,
				LogMessage:     "✗ Unable to complete check: An unexpected error occurred.",
				ProgressedAt:   synctestTime,
				Title:          &wrapperspb.StringValue{Value: "License compliance check encountered an error"},
			})
	})
}

func TestProtoStatusMapping(t *testing.T) {
	tests := []struct {
		name           string
		checkJob       *models.CheckJob
		expectedStatus entities.CheckJobStatus
	}{
		{"starting", &models.CheckJob{Status: models.Starting}, entities.CheckJobStatus_CHECK_JOB_STATUS_STARTING},
		{"waiting", &models.CheckJob{Status: models.Waiting}, entities.CheckJobStatus_CHECK_JOB_STATUS_WAITING},
		{"running", &models.CheckJob{Status: models.Running}, entities.CheckJobStatus_CHECK_JOB_STATUS_RUNNING},
		{"pass", &models.CheckJob{Status: models.Pass}, entities.CheckJobStatus_CHECK_JOB_STATUS_PASS},
		{"fail", &models.CheckJob{Status: models.Fail}, entities.CheckJobStatus_CHECK_JOB_STATUS_FAIL},
		{"error", &models.CheckJob{Status: models.Error}, entities.CheckJobStatus_CHECK_JOB_STATUS_ERROR},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			synctest.Test(t, func(t *testing.T) {
				tp := testpublisher.NewTestPublisher(t)

				tp.PublishLicenseCheckProgress(t.Context(), tt.checkJob)

				tp.AssertMessagePublished(t, "github.dependencygraph.v1.PullRequestLicenseCheckProgressed",
					&dependencygraphv1.PullRequestLicenseCheckProgressed{
						CheckJobStatus: tt.expectedStatus,
						LogMessage:     tt.checkJob.LogMessage(),
						ProgressedAt:   synctestTime,
					})
			})
		})
	}
}

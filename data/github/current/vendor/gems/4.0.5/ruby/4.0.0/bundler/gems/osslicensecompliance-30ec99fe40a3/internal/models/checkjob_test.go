package models_test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"github.com/github/osslicensecompliance/internal/models"
)

func TestCheckJob_LogMessage(t *testing.T) {
	tests := []struct {
		name     string
		checkJob *models.CheckJob
		expected string
	}{
		{
			name:     "starting",
			checkJob: &models.CheckJob{Status: models.Starting},
			expected: "Starting license check...",
		},
		{
			name:     "waiting with snapshots",
			checkJob: &models.CheckJob{Status: models.Waiting, ReceivedSnapshots: 2, ExpectedSnapshots: 5},
			expected: "Waiting for dependency snapshots (2/5 received)...",
		},
		{
			name:     "running",
			checkJob: &models.CheckJob{Status: models.Running},
			expected: "Evaluating dependencies against license policy...",
		},
		{
			name:     "pass",
			checkJob: &models.CheckJob{Status: models.Pass},
			expected: "✓ License check passed",
		},
		{
			name:     "fail",
			checkJob: &models.CheckJob{Status: models.Fail},
			expected: "✗ License check completed with violations. See the comment from license-compliance-bot on this pull request for details.",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.checkJob.LogMessage())
		})
	}
}

func TestCheckJob_Title(t *testing.T) {
	tests := []struct {
		name       string
		checkJob   *models.CheckJob
		alertCount int
		expected   string
	}{
		{
			name:       "pass",
			checkJob:   &models.CheckJob{Status: models.Pass},
			alertCount: 0,
			expected:   "No new license compliance alerts in code changed by this pull request",
		},
		{
			name:       "fail with zero alerts",
			checkJob:   &models.CheckJob{Status: models.Fail},
			alertCount: 0,
			expected:   "License check failed",
		},
		{
			name:       "fail with one alert",
			checkJob:   &models.CheckJob{Status: models.Fail},
			alertCount: 1,
			expected:   "1 new license compliance alert",
		},
		{
			name:       "fail with multiple alerts",
			checkJob:   &models.CheckJob{Status: models.Fail},
			alertCount: 5,
			expected:   "5 new license compliance alerts",
		},
		{
			name:       "error",
			checkJob:   &models.CheckJob{Status: models.Error},
			alertCount: 0,
			expected:   "License compliance check encountered an error",
		},
		{
			name:       "non-terminal status returns empty",
			checkJob:   &models.CheckJob{Status: models.Running},
			alertCount: 0,
			expected:   "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.checkJob.Title(tt.alertCount))
		})
	}
}

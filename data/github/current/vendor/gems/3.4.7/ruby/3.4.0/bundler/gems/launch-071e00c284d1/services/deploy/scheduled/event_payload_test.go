package scheduled

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/types"
)

const (
	cronSchedule     = "*/5 * * * *"
	workflowPath     = ".github/workflows/scheduled.yml"
	userOwnedRepoID  = types.GlobalID("MDEwOlJlcG9zaXRvcnkyMDUwMDM2ODE=") // 205003681
	orgRepoID        = types.GlobalID("MDEwOlJlcG9zaXRvcnkyMTcxMTE1NTU=") // 217111555
	enterpriseRepoID = types.GlobalID("MDEwOlJlcG9zaXRvcnkzMzYwNzEzNTU=") // 336071355
)

func TestCreateEventPayload(t *testing.T) {
	repoEventMap := repositoryEventMap(t)
	tests := []struct {
		name                 string
		repoGID              types.GlobalID
		zeroRepoID           bool
		eventDetails         string
		eventDetailsErr      error
		expectedEventPayload *flowevents.ScheduleEventPayload
	}{
		{
			name:       "no repository database ID",
			repoGID:    userOwnedRepoID,
			zeroRepoID: true,
			expectedEventPayload: &flowevents.ScheduleEventPayload{
				Schedule: cronSchedule,
				Workflow: workflowPath,
			},
		},
		{
			name:            "error fetching event details",
			repoGID:         userOwnedRepoID,
			eventDetailsErr: errors.New("fetching event details"),
			expectedEventPayload: &flowevents.ScheduleEventPayload{
				Schedule: cronSchedule,
				Workflow: workflowPath,
			},
		},
		{
			name:                 "user owned repository",
			repoGID:              userOwnedRepoID,
			eventDetails:         repoEventMap[userOwnedRepoID].eventDetailsResponse,
			expectedEventPayload: repoEventMap[userOwnedRepoID].expectedEventPayload,
		},
		{
			name:                 "organization repository",
			repoGID:              orgRepoID,
			eventDetails:         repoEventMap[orgRepoID].eventDetailsResponse,
			expectedEventPayload: repoEventMap[orgRepoID].expectedEventPayload,
		},
		{
			name:                 "enterprise repository",
			repoGID:              enterpriseRepoID,
			eventDetails:         repoEventMap[enterpriseRepoID].eventDetailsResponse,
			expectedEventPayload: repoEventMap[enterpriseRepoID].expectedEventPayload,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			sr := schedules.ScheduleRun{
				Schedule:         cronSchedule,
				WorkflowFilePath: workflowPath,
				RepositoryNodeID: tt.repoGID,
			}

			_, repoID, err := tt.repoGID.Decode()
			require.NoError(t, err)

			ghTwirpClient := &ghtwirp.MockClient{}
			if tt.eventDetails != "" || tt.eventDetailsErr != nil {
				ghTwirpClient.On("GetRepositoryEventDetails", mock.Anything, repoID).Return(tt.eventDetails, tt.eventDetailsErr)
			}

			var eventPayload *flowevents.ScheduleEventPayload
			if tt.zeroRepoID {
				repoID = 0
			}
			eventPayload = createEventPayload(context.Background(), ghTwirpClient, logger.NullLogger(), repoID, sr)

			require.Equal(t, tt.expectedEventPayload, eventPayload)
		})
	}
}

type event struct {
	eventDetailsResponse string
	expectedEventPayload *flowevents.ScheduleEventPayload
}

func repositoryEventMap(t *testing.T) map[types.GlobalID]event {
	eventDetailsMap := make(map[types.GlobalID]event, 3)

	userOwnedRepoEventDetails, err := os.ReadFile(filepath.Join("fixtures", "user_repository_details.json"))
	require.NoError(t, err)

	var userRepoPayload map[string]map[string]any
	err = json.Unmarshal([]byte(userOwnedRepoEventDetails), &userRepoPayload)
	require.NoError(t, err)

	eventDetailsMap[userOwnedRepoID] = event{
		eventDetailsResponse: string(userOwnedRepoEventDetails),
		expectedEventPayload: &flowevents.ScheduleEventPayload{
			Schedule:   cronSchedule,
			Workflow:   workflowPath,
			Repository: userRepoPayload["repository"],
		},
	}

	orgRepoEventDetails, err := os.ReadFile(filepath.Join("fixtures", "organization_repository_details.json"))
	require.NoError(t, err)

	var orgRepoPayload map[string]map[string]any
	err = json.Unmarshal([]byte(orgRepoEventDetails), &orgRepoPayload)
	require.NoError(t, err)

	eventDetailsMap[orgRepoID] = event{
		eventDetailsResponse: string(orgRepoEventDetails),
		expectedEventPayload: &flowevents.ScheduleEventPayload{
			Schedule:     cronSchedule,
			Workflow:     workflowPath,
			Repository:   orgRepoPayload["repository"],
			Organization: orgRepoPayload["organization"],
		},
	}

	enterpriseRepoEventDetails, err := os.ReadFile(filepath.Join("fixtures", "enterprise_repository_details.json"))
	require.NoError(t, err)

	var enterpriseRepoPayload map[string]map[string]any
	err = json.Unmarshal([]byte(enterpriseRepoEventDetails), &enterpriseRepoPayload)
	require.NoError(t, err)

	eventDetailsMap[enterpriseRepoID] = event{
		eventDetailsResponse: string(enterpriseRepoEventDetails),
		expectedEventPayload: &flowevents.ScheduleEventPayload{
			Schedule:     cronSchedule,
			Workflow:     workflowPath,
			Repository:   enterpriseRepoPayload["repository"],
			Organization: enterpriseRepoPayload["organization"],
			Enterprise:   enterpriseRepoPayload["enterprise"],
		},
	}
	return eventDetailsMap
}

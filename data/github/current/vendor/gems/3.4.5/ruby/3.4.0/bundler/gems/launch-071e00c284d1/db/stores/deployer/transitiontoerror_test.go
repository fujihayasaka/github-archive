package deployer

import (
	"context"
	"database/sql"
	"fmt"
	"os"
	"testing"

	"github.com/facebookgo/clock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/payloads"
	"github.com/github/launch/mysqldb"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/asql"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/utils/testutils"
	"github.com/github/launch/workflowbuild/build"
)

func Test_TransitionToError(t *testing.T) {
	tests := []struct {
		name        string
		existingRow bool
	}{
		{
			name:        "row already exists",
			existingRow: true,
		},
		{
			name:        "row not found",
			existingRow: false,
		},
	}

	obs := observability.NewTestObservability()

	payloadsConn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("ACTIONS_PAYLOADS_TEST_DATABASE_URL"))
	require.NoError(t, err)

	conn, err := mysqldb.NewDB(statter.NullStatter(), os.Getenv("LAUNCH_DEPLOYER_TEST_DATABASE_URL"))
	require.NoError(t, err)

	clock := clock.NewMock()
	pdb := asql.New(payloadsConn, obs.Logger, obs.Statter, testutils.NewNoopBreaker(), asql.PayloadsCluster)
	payloadsModel := payloads.New(pdb, obs.Logger, obs.Statter)
	adb := asql.New(conn, obs.Logger, obs.Statter, testutils.NewNoopBreaker(), asql.LaunchCluster)

	executingActorID := types.GlobalID("MDQ6VXNlcjE=")
	triggeringActorID := types.GlobalID("MDQ6VXNlcjE2NjMxMDQy")

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			mockTwirpClient := ghtwirp.NewMockClient(t)
			globalIDMigrator := NewGlobalIDMigrator(mockTwirpClient)

			executionsRepo := NewWorkflowBuildExecutionsRepository(adb, obs, clock, globalIDMigrator)
			builds := NewWorkflowBuildsRepository(adb, obs.Logger, obs.Statter, clock, payloadsModel, executionsRepo, globalIDMigrator, false)

			ctx := context.Background()

			_, err = conn.Exec(`TRUNCATE workflow_builds`)
			require.NoError(t, err)

			b, workflowMetadata, checkSuiteState, _ := makeBuild(t, WithEventPayload([]byte("test")))

			// Mock GetNextGlobalID for Perist
			mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkSuiteState.RepositoryID.String()).Return(types.GlobalID("R_kgDNBTk"), nil).Once()
			mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, executingActorID.String()).Return(types.NilGlobalID, nil).Once()
			mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, triggeringActorID.String()).Return(types.NilGlobalID, nil).Once()

			buildID, _, eventTime, persistedPayload, err := builds.Persist(ctx, b, checkSuiteState.RepositoryID, checkSuiteState.EventSHA, checkSuiteState.EventRef, checkSuiteState.FlowIdentifier, workflowMetadata, &tokens.PermissionSettings{}, b.EventPayload, executingActorID, triggeringActorID, ghtenant.GitHubTenant{})
			require.NoError(t, err)
			assert.True(t, persistedPayload)
			assert.False(t, eventTime.IsZero())

			// SetCheckSuiteInformation will always fetch the check suite next ID
			// Expect a second call from TransitionToError
			mockTwirpClient.EXPECT().GetNextGlobalID(mock.Anything, checkSuiteState.CheckSuiteIDPair.GlobalID.String()).Return(types.GlobalID("CS_kwDOEDT6U84yStDE"), nil).Twice()

			err = builds.SetCheckSuiteInformation(ctx, buildID, checkSuiteState.CheckSuiteIDPair.GlobalID, checkSuiteState.WorkflowRunID, checkSuiteState.WorkflowRunNumber)
			require.NoError(t, err)

			if tt.existingRow {
				assertBuildState(t, conn, buildID, build.WorkflowStateNone)

				err := builds.TransitionToError(
					ctx,
					buildID,
					checkSuiteState.CheckSuiteIDPair.GlobalID,
				)
				require.NoError(t, err)

				assertBuildState(t, conn, buildID, build.WorkflowStateFailed)
			} else {
				otherID := buildID + 166

				err := builds.TransitionToError(
					ctx,
					otherID,
					checkSuiteState.CheckSuiteIDPair.GlobalID,
				)
				require.EqualError(t, err, fmt.Sprintf("failed to update existing build row `%v' in TransitionToError", otherID))
			}
		})
	}
}

func assertBuildState(t *testing.T, db *sql.DB, buildID int64, expected build.WorkflowState) {
	var state build.WorkflowState
	var csIDRes, csNextIDRes types.GlobalID
	row := db.QueryRow(`select state, check_suite_id, check_suite_next_id from workflow_builds where id = ?`, buildID)
	require.NoError(t, row.Scan(&state, &csIDRes, &csNextIDRes))
	assert.Equal(t, expected, state)
	assert.Equal(t, csIDRes, csNextIDRes)
}

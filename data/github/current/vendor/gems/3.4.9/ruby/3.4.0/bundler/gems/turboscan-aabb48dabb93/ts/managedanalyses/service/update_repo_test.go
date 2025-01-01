package managedanalyses_test

import (
	"context"
	"testing"

	"github.com/aws/smithy-go/ptr"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/workflows"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestUpdateRepo(t *testing.T) {
	db, ctx, ma, _, mockLauncher, _ := setup(t)
	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningConfigWorkflowNext)

	// Create a CodeqlConfig in the database
	originalConfig := &ts.CodeqlConfig{
		RepositoryID:         repoID,
		RepositoryGRID:       "123456",
		OnboardedByActorGRID: "123abc",
		CreatedByActorLogin:  "abc",
		Languages:            []string{"javascript"},
		TemplateVersion:      workflows.NextVersion,
		RunnerLabel:          "anything",
	}
	originalConfig.MakeCurrent()
	dbtest.RequireCreate(t, db, originalConfig)

	// The config also needs an associated run
	run := &ts.CodeqlRun{
		RepositoryID:    repoID,
		WorkflowRunID:   1,
		Status:          ts.CodeqlRunStatus_COMPLETED,
		TriggeringEvent: ts.CodeqlRunTriggeringEvent_VALIDATION,
		RunType:         ts.CodeqlRunType_VALIDATION,
		CodeqlConfigID:  originalConfig.ID,
	}
	dbtest.RequireCreate(t, db, run)
	_, err := createCodeqlRepo(ctx, ma.DataService, repoID, originalConfig, nil)
	require.NoError(t, err)

	// Now use UpdateRepo to update the config
	languages := ts.Languages{"newlanguage"}
	querySuite := ts.QuerySuite_EXTENDED
	threatModel := ts.ThreatModel_REMOTE_LOCAL

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			run.WorkflowRunID = 101
			return nil
		},
	).Times(1)

	_, err = ma.UpdateRepo(ctx,
		repoID, languages, &languages, &querySuite, &threatModel, botActor,
		ts.Ref("refs/heads/main"), ts.OwnerEID(1), ts.CodeqlPacks(""), ptr.String(""))
	require.NoError(t, err)
	// Check the changes have been applied
	// There are now 2 configs stored
	dbtest.RequireCount(t, 2, db.Model(&ts.CodeqlConfig{}))
	// 1 config is staged
	stagedTag := ts.CodeqlConfigTag_STAGED
	dbtest.RequireCount(t, 1, db.Model(&ts.CodeqlConfig{}).Where(&ts.CodeqlConfig{Tag: &stagedTag}))

	var newConfig ts.CodeqlConfig
	err = db.Model(&ts.CodeqlConfig{}).Where(&ts.CodeqlConfig{Tag: &stagedTag}).First(&newConfig).Error
	require.NoError(t, err)

	// The new values are present in the staged config
	require.Equal(t, languages, newConfig.Languages)
	require.Equal(t, querySuite.QuerySuiteType(), newConfig.QuerySuiteType)
	require.Equal(t, botActor.GRID, newConfig.OnboardedByActorGRID)
	require.Equal(t, botActor.Login, newConfig.CreatedByActorLogin)
	require.Equal(t, threatModel, newConfig.ThreatModel)
	require.Equal(t, originalConfig.TemplateVersion, newConfig.TemplateVersion)
	require.Equal(t, newConfig.RunnerLabel, "")

	// But if we set the changed configurable fields to the original values then the configs are equivalent, demonstrating nothing else relevant changed
	newConfig.Languages = originalConfig.Languages
	newConfig.InitialLanguages = originalConfig.InitialLanguages
	newConfig.QuerySuiteType = originalConfig.QuerySuiteType
	newConfig.ThreatModel = originalConfig.ThreatModel
	require.True(t, originalConfig.IsEquivalentIgnoringRunnerLabel(&newConfig))
}

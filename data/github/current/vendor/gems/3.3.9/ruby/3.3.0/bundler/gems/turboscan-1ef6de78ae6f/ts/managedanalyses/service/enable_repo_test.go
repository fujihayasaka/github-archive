package managedanalyses_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestEnableRepo_RequireDefaultRefForOnboarding(t *testing.T) {
	noLangs := ts.Languages{}
	pythonLangs := ts.Languages{"python"}
	emptyRef := ts.Ref{}
	ref := ts.Ref("ref")

	type testCase struct {
		selectedLanguages ts.Languages
		defaultRef        ts.Ref
		expectedSuccess   bool
	}

	tests := []testCase{
		{noLangs, emptyRef, true},
		{noLangs, ref, true},
		{pythonLangs, emptyRef, false},
		{pythonLangs, ref, true},
	}

	_, ctx, ma, mockESS, mockLauncher, _ := setup(t)

	mockESS.EXPECT().PublishStatusForDefaultSetup(gomock.Any(), gomock.Any(), gomock.Any()).DoAndReturn(
		func(context.Context, ts.RepositoryEID, ts.EnablementReason) {},
	).Times(4)

	mockLauncher.EXPECT().RunDynamicWorkflow(gomock.Any(), gomock.Any()).DoAndReturn(
		func(ctx context.Context, run *ts.CodeqlRun) error {
			// Side-effect from this call
			run.WorkflowRunID = 123
			return nil
		},
	)

	for idx, tc := range tests {
		_, err := ma.EnableRepo(
			ctx,
			ts.RepositoryEID(idx+1),
			tc.selectedLanguages,
			tc.selectedLanguages,
			ts.QuerySuite_DEFAULT,
			ts.ThreatModel_REMOTE,
			botActor,
			ts.RepositoryGRID("grid"),
			tc.defaultRef,
			ts.OwnerEID(1),
			false,
			"",
			ts.JavaExtractionOptions_TRACED,
			ts.CSharpExtractionOptions_TRACED,
			ts.CodeqlPacks(""),
		)

		if tc.expectedSuccess {
			require.NoError(t, err, "test case %d - Langs: %v, Ref: %v, err: %v", idx, tc.selectedLanguages, tc.defaultRef, err)
		} else {
			require.Error(t, err, "test case %d - Langs: %v, Ref: %v", idx, tc.selectedLanguages, tc.defaultRef)
		}
	}
}

func TestEnableRepo_SetsExtractionOptions(t *testing.T) {
	_, ctx, ma, mockESS, _, _ := setup(t)

	mockESS.EXPECT().PublishStatusForDefaultSetup(gomock.Any(), gomock.Any(), gomock.Any()).DoAndReturn(
		func(context.Context, ts.RepositoryEID, ts.EnablementReason) {},
	)

	_, err := ma.EnableRepo(ctx,
		ts.RepositoryEID(1),
		ts.Languages{"ruby"},
		ts.Languages{},
		ts.QuerySuite_DEFAULT,
		ts.ThreatModel_REMOTE,
		&ts.ActorGRIDLogin{GRID: "grid", Login: "login"},
		ts.RepositoryGRID("grid"),
		[]byte("main"),
		ts.OwnerEID(1),
		false,
		"",
		ts.JavaExtractionOptions_TRACED,
		ts.CSharpExtractionOptions_TRACED,
		ts.CodeqlPacks(""),
	)
	require.NoError(t, err)

	out, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	require.NoError(t, err)
	require.Equal(t, ts.JavaExtractionOptions_TRACED, out.JavaExtractionOptions)
	require.Equal(t, ts.CSharpExtractionOptions_TRACED, out.CSharpExtractionOptions)
}

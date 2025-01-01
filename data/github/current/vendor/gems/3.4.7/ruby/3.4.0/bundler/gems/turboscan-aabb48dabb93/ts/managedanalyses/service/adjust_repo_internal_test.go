package managedanalyses

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
)

func TestIsValidAdjustment(t *testing.T) {
	// Nominal case: ["go", "java", "python"] -> ["go", "python"]
	// No-Op case: ["go", "java", "python"] -> ["go", "java", "python"]
	// Error case: ["go", "java", "python"] -> ["go", "java", "python", "c++"]

	tests := []struct {
		old      ts.Languages
		new      ts.Languages
		expected bool
	}{
		{ts.Languages{"go", "java", "python"}, ts.Languages{"go", "python"}, true},
		{ts.Languages{"go", "java", "python"}, ts.Languages{"go", "java", "python"}, true},
		{ts.Languages{"go", "java", "python"}, ts.Languages{"go", "java", "python", "c++"}, false},
	}

	for _, tc := range tests {
		actual := isValidAdjustment(&ts.CodeqlConfig{Languages: tc.old}, tc.new)
		if actual != tc.expected {
			t.Errorf("isValidAdjustment(%v, %v) = %v, want %v", tc.old, tc.new, actual, tc.expected)
		}
	}
}

func TestAdjustRepo_EnablingState(t *testing.T) {
	// Only allow adjusting a repo that is Onboarding (ENABLING state)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	adjustCodeqlConfig := func(ctx context.Context, configID ts.CodeqlConfigID, newLanguages ts.Languages, newWorkflow string) error {
		return nil
	}

	oldLangs := ts.Languages{"go", "java", "python"}
	newLangs := ts.Languages{"go", "python"}

	tests := []struct {
		repo              ts.CodeqlRepo
		expectedErr       error
		callingWorkflowID ts.WorkflowRunEID
	}{
		// Repo is onboarding
		{repo: ts.CodeqlRepo{StagedConfig: &ts.CodeqlConfig{Languages: oldLangs}}, expectedErr: nil},
		// Repo is upgrading
		{repo: ts.CodeqlRepo{StagedConfig: &ts.CodeqlConfig{Languages: oldLangs}, CurrentConfig: &ts.CodeqlConfig{Languages: oldLangs}}, expectedErr: ts.ErrNotOnboarding},
		// Repo is onboarded
		{repo: ts.CodeqlRepo{CurrentConfig: &ts.CodeqlConfig{Languages: oldLangs}}, expectedErr: ts.ErrNotOnboarding},
		// Repo is offboarded
		{repo: ts.CodeqlRepo{}, expectedErr: ts.ErrNotOnboarding},
		// The calling workflow id matches the validation run
		{repo: ts.CodeqlRepo{StagedConfig: &ts.CodeqlConfig{Languages: oldLangs, ValidationRun: &ts.CodeqlRun{WorkflowRunID: 42}}}, callingWorkflowID: 42, expectedErr: nil},
		// The calling workflow id does not match the validation run
		{repo: ts.CodeqlRepo{StagedConfig: &ts.CodeqlConfig{Languages: oldLangs, ValidationRun: &ts.CodeqlRun{WorkflowRunID: 42}}}, callingWorkflowID: 43, expectedErr: ts.ErrWrongWorkflowRun},
	}

	for idx, tc := range tests {
		getCodeqlRepo := func(context.Context, ts.RepositoryEID) (*ts.CodeqlRepo, error) {
			return &tc.repo, nil
		}
		codeQLWorkflow := func(*ts.CodeqlConfig) (string, error) {
			return "", nil
		}
		err := adjustRepo(ctx, getCodeqlRepo, adjustCodeqlConfig, codeQLWorkflow, repoID, newLangs, tc.callingWorkflowID)
		if tc.expectedErr != nil && !errors.Is(err, tc.expectedErr) {
			t.Errorf("Test %d: Expected error '%v', but got '%v'", idx, tc.expectedErr, err)
		} else if tc.expectedErr == nil && err != nil {
			t.Errorf("Test %d: Expected no error, but got '%v'", idx, err)
		}
	}
}

func TestAdjustRepo(t *testing.T) {
	// Check that we are indeed trying to update the staged config
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	oldLangs := ts.Languages{"go", "java", "python"}
	newLangs := ts.Languages{"go", "python"}
	runID := ts.WorkflowRunEID(42)

	getCodeqlRepo := func(context.Context, ts.RepositoryEID) (*ts.CodeqlRepo, error) {
		return &ts.CodeqlRepo{
			StagedConfig: &ts.CodeqlConfig{
				Languages:     oldLangs,
				ValidationRun: &ts.CodeqlRun{WorkflowRunID: runID},
			},
		}, nil
	}

	codeQLWorkflow := func(*ts.CodeqlConfig) (string, error) {
		return "new workflow", nil
	}

	adjustCodeqlConfig := func(ctx context.Context, configID ts.CodeqlConfigID, newLanguages ts.Languages, newWorkflow string) error {
		// Assert updated languages
		require.Equal(t, newLangs, newLanguages)
		// Assert updated workflow
		require.Equal(t, "new workflow", newWorkflow)
		return nil
	}

	err := adjustRepo(ctx, getCodeqlRepo, adjustCodeqlConfig, codeQLWorkflow, repoID, newLangs, runID)
	require.NoError(t, err)
}

package workflows_test

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/workflows"
	"github.com/stretchr/testify/require"
)

func TestGetWorkflowTemplate(t *testing.T) {
	ctx := context.Background()
	repo := ts.RepositoryEID(123)
	tl := workflows.NewLibrary()

	// If the FF is off, we get the stable workflow template
	flipper.WithFeatureDisabled(ctx, flipper.CodeScanningConfigWorkflowNext)
	wt := tl.GetWorkflowTemplate(ctx, repo)
	require.NotNil(t, wt)
	require.Equal(t, wt.Version, workflows.StableVersion)

	// If the FF is on, we get the next workflow template
	flipper.WithFeatureEnabled(ctx, flipper.CodeScanningConfigWorkflowNext)
	wt = tl.GetWorkflowTemplate(ctx, repo)
	require.NotNil(t, wt)
	require.Equal(t, wt.Version, workflows.StableVersion)
}

func TestGetWorkflowTemplate_UseCorrectVersion(t *testing.T) {
	tl := workflows.NewLibrary()
	ctx := context.Background()

	ctx = flipper.WithFeatureDisabled(ctx, flipper.CodeScanningConfigWorkflowNext)
	wt := tl.GetWorkflowTemplate(ctx, 0)
	require.NotNil(t, wt)
	require.Equal(t, wt.Version, workflows.StableVersion)

	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningConfigWorkflowNext)
	wt = tl.GetWorkflowTemplate(ctx, 0)
	require.NotNil(t, wt)
	require.Equal(t, wt.Version, workflows.NextVersion)
}

func TestGetWorkflowTemplateByVersion(t *testing.T) {
	tl := workflows.NewLibrary()
	wt := tl.GetWorkflowTemplateByVersion(context.Background(), ts.RepositoryEID(123), "potato")
	require.NotNil(t, wt)
	require.Equal(t, wt.Version, "potato")
}

func TestGetWorkflowTemplate_ForcedNext(t *testing.T) {
	tl := workflows.NewLibrary(workflows.WithForceNextVersion(true))
	wt := tl.GetWorkflowTemplate(context.Background(), 0)
	require.NotNil(t, wt)
	require.Equal(t, wt.Version, workflows.NextVersion)
}

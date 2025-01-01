package ghapi_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/github/turbocassette/recorder"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/ghapi"
	gogh "github.com/google/go-github/v52/github"
	"github.com/stretchr/testify/require"
)

func TestGetWorkflowRunAnnotations(t *testing.T) {
	ctx := context.Background()
	repoID := ts.RepositoryEID(123)
	wrID := ts.WorkflowRunEID(456)

	// Use a cassette for the API calls to gh/gh
	rec, err := recorder.NewAsMode("./testdata/get-workflow-run-annotations.yml", recorder.ModeReplaying, nil)
	require.NoError(t, err)

	c := gogh.NewClient(&http.Client{Transport: rec})

	data, err := ghapi.GetWorkflowRunAnnotations(ctx, c, repoID, wrID)
	require.NoError(t, err)
	require.NotNil(t, data)

	// Check a few key fields are parsed correctly
	require.Equal(t, repoID, data.RepositoryID)
	require.Equal(t, wrID, data.WorkflowRunID)
	require.Equal(t, int64(12672930783), data.CheckSuiteID)
	require.Equal(t, "completed", data.CheckSuiteStatus)
	require.Equal(t, "cancelled", data.CheckSuiteConclusion)
	require.Len(t, data.CheckRuns, 1)
	require.Len(t, data.CheckRuns[0].Annotations, 2)
	require.Equal(t, "failure", data.CheckRuns[0].Annotations[0].AnnotationLevel)
}

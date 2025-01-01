package jobs

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-stats"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turbocassette/recorder"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/ghapi"
	managedanalyses "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	gogh "github.com/google/go-github/v52/github"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

type Entry struct {
	Key  string
	Tags string
}

type MockStats struct {
	stats.Client

	memory map[Entry]int64
}

func NewMockStats() *MockStats {
	return &MockStats{
		memory: map[Entry]int64{},
	}
}

func (m *MockStats) Counter(key string, tags stats.Tags, value int64) {
	entry := Entry{
		Key:  key,
		Tags: fmt.Sprint(tags),
	}
	memValue := m.memory[entry]
	m.memory[entry] = memValue + value
}

type MockManagedAnalysesHydroPublisher struct{}

func (p *MockManagedAnalysesHydroPublisher) WorkflowRunAnnotationsBatch(context.Context, []*tshydro.WorkflowRunAnnotation) error {
	return nil
}

func TestPublishAnnotationsStats(t *testing.T) {
	// Setup job
	repoID := ts.RepositoryEID(123)
	ownerID := ts.OwnerEID(456)
	workflowRunID := ts.WorkflowRunEID(789)
	job := PublishWorkflowRunAnnotations{
		RepoID:        repoID,
		OwnerID:       ownerID,
		WorkflowRunID: workflowRunID,
	}

	// Setup context
	ctx := context.Background()

	// Setup instrumenters
	mockStats := NewMockStats()
	ctx = appctx.WithStats(ctx, mockStats)

	// Setup services
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()
	ghAPI := mocks.NewMockWorkflowRunAnnotationsGetter(mockCtrl)
	services := &aqueduct.TSServices{
		ManagedAnalyses: &managedanalyses.ManagedAnalyses{
			GitHubApiClient: ghAPI,
			HydroPublisher:  &MockManagedAnalysesHydroPublisher{},
		},
	}

	// If there is an error in the inner perform, we emit the right counter to DD and don't return an error
	ghAPI.EXPECT().GetWorkflowRunAnnotations(gomock.Any(), ownerID, repoID, workflowRunID).Return(nil, ghapi.ErrWorkflowRunNotCompleted).Times(1)
	err := job.Perform(ctx, services)
	require.NoError(t, err)
	errorEntry := Entry{Key: "default_setup.publish_annotations", Tags: fmt.Sprint(stats.Tags{"result": "error"})}
	successEntry := Entry{Key: "default_setup.publish_annotations", Tags: fmt.Sprint(stats.Tags{"result": "success"})}
	require.Equal(t, mockStats.memory[errorEntry], int64(1))
	require.Equal(t, mockStats.memory[successEntry], int64(0))

	// reset the stats
	mockStats.memory = map[Entry]int64{}

	// If there is no error in the inner perform, we emit the right counter to DD and don't return an error
	ghAPI.EXPECT().GetWorkflowRunAnnotations(gomock.Any(), ownerID, repoID, workflowRunID).Return(&ghapi.WorkflowRunAnnotations{}, nil).Times(1)
	err = job.Perform(ctx, services)
	require.NoError(t, err)
	require.Equal(t, mockStats.memory[errorEntry], int64(0))
	require.Equal(t, mockStats.memory[successEntry], int64(1))
}

type WorkflowRunAnnotationsGetter struct {
	client *gogh.Client
}

func (annotationsGetter WorkflowRunAnnotationsGetter) GetWorkflowRunAnnotations(ctx context.Context, ownerID ts.OwnerEID, repoID ts.RepositoryEID, wrID ts.WorkflowRunEID) (*ghapi.WorkflowRunAnnotations, error) {
	return ghapi.GetWorkflowRunAnnotations(ctx, annotationsGetter.client, repoID, wrID)
}

func TestPublishAnnotations(t *testing.T) {
	repoID := ts.RepositoryEID(123)
	ownerID := ts.OwnerEID(456)
	workflowRunID := ts.WorkflowRunEID(456)
	job := PublishWorkflowRunAnnotations{
		RepoID:        repoID,
		OwnerID:       ownerID,
		WorkflowRunID: workflowRunID,
	}
	ctx := context.Background()
	mockCtrl := gomock.NewController(t)
	defer mockCtrl.Finish()

	// Use a cassette for the API calls to gh/gh
	rec, err := recorder.New("../ghapi/testdata/get-workflow-run-annotations.yml")
	require.NoError(t, err)

	c := gogh.NewClient(&http.Client{Transport: rec})
	annotationsGetter := WorkflowRunAnnotationsGetter{
		client: c,
	}

	require.NoError(t, job.perform(ctx, annotationsGetter, &MockManagedAnalysesHydroPublisher{}))
}

func TestSerializeAnnotations(t *testing.T) {
	// Returns nothing if there is no data
	annotations := &ghapi.WorkflowRunAnnotations{}
	messages := serializeAnnotations(annotations)
	assert.Equal(t, 0, len(messages))

	// Returns nothing if there are no annotations
	cr1 := ghapi.CheckRun{
		ID:          1,
		Name:        "CheckRun1",
		Status:      "completed",
		Conclusion:  "failed",
		StartedAt:   time.Now(),
		CompletedAt: time.Now(),
		Annotations: []ghapi.Annotation{},
	}
	cr2 := ghapi.CheckRun{
		ID:          2,
		Name:        "CheckRun2",
		Status:      "completed",
		Conclusion:  "failed",
		StartedAt:   time.Now(),
		CompletedAt: time.Now(),
		Annotations: []ghapi.Annotation{},
	}
	annotations = &ghapi.WorkflowRunAnnotations{
		WorkflowRunID:        ts.WorkflowRunEID(789),
		RepositoryID:         ts.RepositoryEID(123),
		CheckSuiteID:         1,
		CheckSuiteStatus:     "completed",
		CheckSuiteConclusion: "failed",
		CheckSuiteCreatedAt:  time.Now(),
		CheckSuiteUpdatedAt:  time.Now(),
		CheckRuns:            []ghapi.CheckRun{cr1, cr2},
	}

	messages = serializeAnnotations(annotations)
	assert.Equal(t, 0, len(messages))

	// Returns the annotations
	cr1Annotation1 := ghapi.Annotation{
		Path:            "path1",
		Title:           "title1",
		Message:         "message1",
		AnnotationLevel: "warning",
	}
	cr1Annotation2 := ghapi.Annotation{
		Path:            "path2",
		Title:           "title2",
		Message:         "message2",
		AnnotationLevel: "error",
	}
	cr1.Annotations = append(cr1.Annotations, cr1Annotation1, cr1Annotation2)

	cr2Annotation1 := ghapi.Annotation{
		Path:            "path3",
		Title:           "title3",
		Message:         "message3",
		AnnotationLevel: "warning",
	}
	cr2.Annotations = append(cr2.Annotations, cr2Annotation1)

	annotations.CheckRuns = []ghapi.CheckRun{cr1, cr2}
	messages = serializeAnnotations(annotations)
	assert.Equal(t, 3, len(messages))

	// annotation 0
	assert.Equal(t, int64(annotations.WorkflowRunID), messages[0].WorkflowRunId)
	assert.Equal(t, int64(annotations.RepositoryID), messages[0].RepositoryId)
	assert.Equal(t, annotations.CheckSuiteID, messages[0].CheckSuiteId)
	assert.Equal(t, cr1.ID, messages[0].CheckRunId)
	assert.Equal(t, cr1Annotation1.Path, messages[0].Path)

	// annotation 1
	assert.Equal(t, int64(annotations.WorkflowRunID), messages[1].WorkflowRunId)
	assert.Equal(t, int64(annotations.RepositoryID), messages[1].RepositoryId)
	assert.Equal(t, annotations.CheckSuiteID, messages[1].CheckSuiteId)
	assert.Equal(t, cr1.ID, messages[1].CheckRunId)
	assert.Equal(t, cr1Annotation2.Path, messages[1].Path)

	// annotation 2
	assert.Equal(t, int64(annotations.WorkflowRunID), messages[2].WorkflowRunId)
	assert.Equal(t, int64(annotations.RepositoryID), messages[2].RepositoryId)
	assert.Equal(t, annotations.CheckSuiteID, messages[2].CheckSuiteId)
	assert.Equal(t, cr2.ID, messages[2].CheckRunId)
	assert.Equal(t, cr2Annotation1.Path, messages[2].Path)
}

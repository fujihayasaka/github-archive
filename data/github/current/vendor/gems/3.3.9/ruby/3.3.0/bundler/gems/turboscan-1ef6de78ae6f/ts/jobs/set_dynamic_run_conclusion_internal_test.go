package jobs

import (
	"context"
	"testing"

	"github.com/pkg/errors"

	"github.com/github/turboscan/ts"
	ma "github.com/github/turboscan/ts/managedanalyses"
	"github.com/stretchr/testify/require"
)

var _ ma.CodeqlDB = (*CodeqlDBError)(nil)

// CodeqlDBError is a simple mock for the Codeql interface that only returns an error value
type CodeqlDBError struct {
	ma.CodeqlDB
	err error
}

func (m CodeqlDBError) GetCodeqlRun(context.Context, ts.RepositoryEID, ts.WorkflowRunEID) (*ts.CodeqlRun, error) {
	return nil, m.err
}

func TestSetDynamicRunConclusionPerform_Errors(t *testing.T) {
	job := SetDynamicRunConclusion{}
	db := CodeqlDBError{}
	updateRepo := func(context.Context, ts.RepositoryEID) error { return nil }
	ctx := context.Background()

	// These are all errors that we know can occur and do not want to retry.
	// Therefore, perform should swallow/ignore these errors.
	ignoreErrors := []error{ts.ErrCodeqlConfigNotFound, ts.ErrCodeqlRunNotFound, ts.ErrWorkflowRunAlreadyCompleted, ts.ErrCodeqlRepoNotFound}
	for _, myErr := range ignoreErrors {
		db.err = myErr
		require.NoError(t, job.perform(ctx, db, updateRepo, nil, nil, nil, false))
		require.NoError(t, job.perform(ctx, db, updateRepo, nil, nil, nil, true))
	}

	// We want to retry some errors
	newError := errors.New("new error")
	db.err = newError
	require.Error(t, job.perform(ctx, db, updateRepo, nil, nil, nil, false))
}

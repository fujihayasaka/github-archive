package managedanalyses_test

import (
	"context"
	"testing"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/jinzhu/gorm"
)

// createCodeqlRepo creates a codeql repo in the database, optionally
// setting the configurations.
func createCodeqlRepo(ctx context.Context, maDB managedanalyses.CodeqlDB,
	repoID ts.RepositoryEID, current *ts.CodeqlConfig, staged *ts.CodeqlConfig,
) (*ts.CodeqlRepo, error) {
	err := maDB.CreateCodeqlRepo(ctx, &ts.CodeqlRepo{RepositoryID: repoID})
	if err != nil {
		return nil, err
	}
	codeqlRepo, err := maDB.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return nil, err
	}

	if current != nil {
		codeqlRepo.CurrentConfigID = &current.ID
	}
	if staged != nil {
		codeqlRepo.StagedConfigID = &staged.ID
	}

	err = maDB.UpdateCodeqlRepo(ctx, codeqlRepo)
	if err != nil {
		return nil, err
	}
	return codeqlRepo, nil
}

type hydroPublisherStub struct{}

func (h hydroPublisherStub) CodeqlRunEvent(ctx context.Context, run *oldtshydro.CodeqlRun) error {
	return nil
}

func newManagedAnalysisService(t *testing.T, db *gorm.DB) *managedanalysis.Service {
	t.Helper()

	return managedanalysis.NewService(db, hydroPublisherStub{})
}

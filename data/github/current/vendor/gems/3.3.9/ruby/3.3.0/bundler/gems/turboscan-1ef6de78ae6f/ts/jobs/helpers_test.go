package jobs_test

import (
	"context"
	"testing"

	oldtshydro "github.com/github/hydro-schemas-go/hydro/schemas/turboscan/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/jinzhu/gorm"
)

func getCurrentConfig(ctx context.Context, maDB managedanalyses.CodeqlDB, repoID ts.RepositoryEID) (*ts.CodeqlConfig, error) {
	codeqlRepo, err := maDB.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return nil, err
	}

	return codeqlRepo.CurrentConfig, nil
}

type hydroPublisherStub struct{}

func (h hydroPublisherStub) CodeqlRunEvent(ctx context.Context, run *oldtshydro.CodeqlRun) error {
	return nil
}

func newManagedAnalysisService(t *testing.T, db *gorm.DB) *managedanalysis.Service {
	t.Helper()

	return managedanalysis.NewService(db, hydroPublisherStub{})
}

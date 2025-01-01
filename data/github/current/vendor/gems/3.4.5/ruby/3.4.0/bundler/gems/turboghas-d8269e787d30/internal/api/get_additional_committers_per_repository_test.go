package api_test

import (
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/simon-engledew/go-vcr"
)

func TestGetAdditionalCommittersPerRepository(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-additional-committers-per-repository", handler, vcr.ReplaceTimestamps)
}

func TestGetAdditionalCommittersPerRepository_IncludesEnterpriseManagedUsers(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-additional-committers-per-repository-enterprise-users", handler, vcr.ReplaceTimestamps)
}

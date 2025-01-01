package api_test

import (
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/simon-engledew/go-vcr"
)

func TestGetCommittersForBusiness(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-committers-for-business", handler, vcr.ReplaceTimestamps)
}

func TestGetCommittersForBusiness_IncludesEnterpriseManagedUsers(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-committers-for-business-enterprise-users", handler, vcr.ReplaceTimestamps)
}

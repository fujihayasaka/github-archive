package api_test

import (
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/simon-engledew/go-vcr"
)

func TestGetAllActiveCommitterForOrgOwner(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-committers-for-owner", handler, vcr.ReplaceTimestamps)
}

func TestGetAllActiveCommitterForUserOwner(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-committers-for-user-owner", handler, vcr.ReplaceTimestamps)
}

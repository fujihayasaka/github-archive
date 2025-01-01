package api_test

import (
	"testing"

	"github.com/github/turboghas/internal/api"
	"github.com/github/turboghas/internal/dbtest"
)

func TestGetOrganizations(t *testing.T) {
	db := dbtest.Seed(t)

	handler := api.New(dbtest.Dual(db))

	replay(t, "get-organizations", handler)
}

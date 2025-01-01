package jobs

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/limits"
	asdb "github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/sarif/store"
	sf "github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/stretchr/testify/require"
)

func TestSuggestedFixTelemetryPerformNotInEnterprise(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	sfDB := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}
	sfServ := sf.New(sfDB, as, arch, ls, mockSpokes, sf.NewMockValidFixGenerator())

	aqueductMock := &aqueduct.AqueductMock{}
	s := &aqueduct.TSServices{
		SuggestedFixes:  sfServ,
		Aqueduct:        aqueductMock,
		IsEnterpriseEnv: true,
	}

	sft := &SuggestedFixTelemetry{}

	require.NoError(t, sft.Perform(ctx, s))
}

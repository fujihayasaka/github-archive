package alert

import (
	"context"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func TestLoadAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	// A loader with no filters should load all alerts.
	setup2alerts(t, db)
	loader := as.NewLoader(&ts.Repository{RepositoryID: 1})
	require.Len(t, loadAllAlerts(t, loader), 2)
}

func TestLoadMaxAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	// A loader with no filters should load all alerts.
	setup2alerts(t, db)
	loader := as.NewLoader(&ts.Repository{RepositoryID: 1})
	loader.SetMaxLoad(1)
	loader.SetBatchSize(1) // The max is not strict so we need to set the batch size to 1 to ensure we only load 1 alert.
	require.Len(t, loadAllAlerts(t, loader), 1)
}

func TestAutofixMetadata(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := TestService(db)

	setup2alerts(t, db)
	loader := as.NewLoader(&ts.Repository{RepositoryID: 1, DefaultRef: []byte("refs/heads/main")})
	alerts := loadAllAlerts(t, loader)
	require.Len(t, alerts, 2)
	// The first alert is not eligible for an autofix, but the second is.
	require.False(t, alerts[0].AutofixEligible)
	require.True(t, alerts[1].AutofixEligible)
	// The first alert does not have any suggested fix, the second does
	require.Nil(t, alerts[0].SuggestedFixAlert)
	require.NotNil(t, alerts[1].SuggestedFixAlert)
	require.Equal(t, ts.SuggestedFixAlertStateValid, alerts[1].SuggestedFixAlert.State)
}

// setup2alerts creates 2 alerts in the database.
func setup2alerts(t *testing.T, db *gorm.DB) {
	t.Helper()
	l1 := &ts.LogicalAlert{ID: 1,
		Number:                1,
		RepositoryID:          1,
		StableAlertIdentifier: []byte("1"),
		SarifIdentifier:       "foo/bar",
		Rule: &ts.Rule{
			Tool: &ts.Tool{
				CanonicalName: ts.ToolName("CodeQL"),
				GUID:          "1",
			},
		},
	}
	dbtest.RequireCreate(t, db, l1)
	p1 := &ts.PhysicalAlert{
		RepositoryID:          1,
		LogicalAlertID:        l1.ID,
		StableAlertIdentifier: []byte("1"),
		LastStateChangeAt:     l1.CreatedAt,
	}
	dbtest.RequireCreate(t, db, p1)
	l2 := &ts.LogicalAlert{ID: 2,
		Number:                2,
		RepositoryID:          1,
		StableAlertIdentifier: []byte("2"),
		SarifIdentifier:       "rb/unsafe-code-construction",
		Rule: &ts.Rule{
			Tool: &ts.Tool{
				CanonicalName: ts.ToolName("CodeQL"),
				GUID:          "2",
			},
		},
	}
	dbtest.RequireCreate(t, db, l2)
	p2 := &ts.PhysicalAlert{
		RepositoryID:          1,
		LogicalAlertID:        l2.ID,
		StableAlertIdentifier: []byte("2"),
		LastStateChangeAt:     l2.CreatedAt,
	}
	dbtest.RequireCreate(t, db, p2)
	sf := &ts.SuggestedFixAlert{
		RepositoryID:       1,
		LogicalAlertNumber: 2,
		State:              ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:     l2.CreatedAt,
		RefBytes:           []byte("refs/heads/main"),
		RequestedAt:        sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, sf)
}

// loadAllAlerts loads all alerts from the loader.
func loadAllAlerts(t *testing.T, loader *Loader) []*ts.LogicalAlert {
	t.Helper()
	ctx := context.Background()
	acc := []*ts.LogicalAlert{}
	require.NoError(t, loader.BatchedLoad(ctx, func(alerts []*ts.LogicalAlert) error {
		acc = append(acc, alerts...)
		return nil
	}))
	return acc
}

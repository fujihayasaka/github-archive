package alert_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/github/turboscan/ts/mysql/alert"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"

	"github.com/github/turboscan/ts/dbtest"
)

func TestLatestAnalysesNotFound(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)
	_, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
		Ref: []byte("refs/heads/main"),
	}, true)
	require.NoError(t, err)
}

func TestLatestAnalysesToolRenamed(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("Golang security checks by gosec")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a1 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv1.ToolID,
		DeliveryID:         d1.ID,
		ToolVersionID:      tv1.ID,
		ToolVersion:        tv1,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
	}

	dbtest.RequireCreate(t, db, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a2 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv2.ToolID,
		DeliveryID:         d2.ID,
		ToolVersionID:      tv2.ID,
		ToolVersion:        tv2,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
	}

	dbtest.RequireCreate(t, db, d2)
	dbtest.RequireCreate(t, db, a2)

	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
	}
}

func TestLatestAnalysesToolRenamed_Was_Outdated(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("Golang security checks by gosec")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a1 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv1.ToolID,
		DeliveryID:         d1.ID,
		ToolVersionID:      tv1.ID,
		ToolVersion:        tv1,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
		IsOutdated:         true,
	}

	dbtest.RequireCreate(t, db, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a2 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv2.ToolID,
		DeliveryID:         d2.ID,
		ToolVersionID:      tv2.ID,
		ToolVersion:        tv2,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
	}

	dbtest.RequireCreate(t, db, d2)
	dbtest.RequireCreate(t, db, a2)

	{
		items, err := as.LatestAnalysisIDsForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		})
		require.NoError(t, err)
		require.Len(t, items, 1)
	}
}

func TestLatestAnalysesToolRenamed_Outdated(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("Golang security checks by gosec")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a1 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv1.ToolID,
		DeliveryID:         d1.ID,
		ToolVersionID:      tv1.ID,
		ToolVersion:        tv1,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
	}

	dbtest.RequireCreate(t, db, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a2 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv2.ToolID,
		DeliveryID:         d2.ID,
		ToolVersionID:      tv2.ID,
		ToolVersion:        tv2,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
		IsOutdated:         true,
	}

	dbtest.RequireCreate(t, db, d2)
	dbtest.RequireCreate(t, db, a2)

	{
		items, err := as.LatestAnalysisIDsForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		})
		require.NoError(t, err)
		require.Len(t, items, 0)
	}
}

func TestLatestAnalysesClearDelivery(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	tool := &ts.Tool{
		CanonicalName:  "CodeQL",
		GUID:           "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, tool)
	tv := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  tool.ID,
	}
	dbtest.RequireCreate(t, db, tv)

	d1 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}

	a1 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv.ToolID,
		DeliveryID:         d1.ID,
		ToolVersionID:      tv.ID,
		ToolVersion:        tv,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
	}

	dbtest.RequireCreate(t, db, d1)
	dbtest.RequireCreate(t, db, a1)

	d2 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{124},
	}

	dbtest.RequireCreate(t, db, d2)
	dbtest.RequireCreate(t, db, &ts.AnalysisMessage{
		Key:          ts.MessageZipInvalidArgs,
		RawArgs:      json.RawMessage("null"),
		RepositoryID: 1,
		DeliveryID:   d2.ID,
	})

	// we should pick up the delivery error as there has not been a successful delivery since
	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
		require.Len(t, items[0].AnalysisMessages, 1)
	}

	d3 := &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710"),
		Ref:          []byte("refs/heads/main"),
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{125},
	}
	dbtest.RequireCreate(t, db, d3)

	a2 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710"),
		AnalysisKey:        "key",
		BaselineID:         &a1.ID,
		ToolID:             tv.ToolID,
		DeliveryID:         d3.ID,
		ToolVersionID:      tv.ID,
		ToolVersion:        tv,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, a2)

	// commit analysis
	require.NoError(t, db.Exec(`UPDATE ts_analyses SET most_recent = id = ?`, a2.ID).Error)

	// the delivery error should have been cleared by the new delivery
	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
		require.Len(t, items[0].AnalysisMessages, 0)
	}
}

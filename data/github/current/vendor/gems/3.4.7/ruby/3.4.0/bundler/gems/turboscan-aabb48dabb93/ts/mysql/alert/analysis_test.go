package alert_test

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/transforms"
)

func TestLatestAnalysesNotFound(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	_, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
		Ref: []byte("refs/heads/main"),
	}, true)

	require.NoError(t, err)
}

func TestLatestAnalysesNotFoundForRef(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("CodeQL")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/another-ref"),
		}, true)
		require.NoError(t, err)
		require.Empty(t, items)
	}
}

func TestLatestAnalysesRespectsDeliveryOriginFilter(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("CodeQL")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	{
		ymlOrigin := ts.DeliveryOrigin_YML
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref:            []byte("refs/heads/main"),
			DeliveryOrigin: &ymlOrigin,
		}, true)
		require.NoError(t, err)
		require.Empty(t, items)
	}

	{
		apiOrigin := ts.DeliveryOrigin_API
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref:            []byte("refs/heads/main"),
			DeliveryOrigin: &apiOrigin,
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
	}
}

func TestLatestAnalysesRespectsToolIDsFilter(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("CodeQL")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref:     []byte("refs/heads/main"),
			ToolIDs: []ts.ToolID{t1.ID + 1},
		}, true)
		require.NoError(t, err)
		require.Empty(t, items)
	}

	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref:     []byte("refs/heads/main"),
			ToolIDs: []ts.ToolID{t1.ID},
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
	}
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

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := delivery()
	dbtest.RequireCreate(t, db, d2)

	a2 := analysis(tv2, d2)
	dbtest.RequireCreate(t, db, a2)

	// `gosec` is the newer name for `Golang security checks by gosec`, so they should be considered the same tool.
	// Therefore, the two analyses will have the same configuration and we'll only return the last analysis.
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

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	a1.IsOutdated = true
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := delivery()
	dbtest.RequireCreate(t, db, d2)

	a2 := analysis(tv2, d2)
	dbtest.RequireCreate(t, db, a2)

	// `gosec` and `Golang security checks by gosec` should still be considered equivalent
	// even if the analysis we have for one of them is outdated
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

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := delivery()
	dbtest.RequireCreate(t, db, d2)

	a2 := analysis(tv2, d2)
	a2.IsOutdated = true
	dbtest.RequireCreate(t, db, a2)

	// `gosec` and `Golang security checks by gosec` should be considered equivalent
	// so therefore marking the more recent analysis (new name) as outdated should
	// affect the older analysis (old name) too, hence no analyses should be returned.
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

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv, d1)
	dbtest.RequireCreate(t, db, a1)

	d2 := delivery()
	d2.CommitOid = ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710")
	d2.CheckRunIds = []uint64{124}
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

	d3 := delivery()
	d3.CommitOid = ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710")
	d3.Failed = false
	d3.CheckRunIds = []uint64{125}
	dbtest.RequireCreate(t, db, d3)

	a2 := analysis(tv, d3)
	a2.CommitOid = ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710")
	a2.BaselineID = &a1.ID
	a2.MostRecent = false
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

func TestMessagesForOldAnalysesAreIgnored(t *testing.T) {
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

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv, d1)
	dbtest.RequireCreate(t, db, a1)

	d2 := delivery()
	d2.CommitOid = ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80710")
	d2.CheckRunIds = []uint64{124}
	dbtest.RequireCreate(t, db, d2)

	dbtest.RequireCreate(t, db, &ts.AnalysisMessage{
		Key:          ts.MessageZipInvalidArgs,
		RawArgs:      json.RawMessage("null"),
		RepositoryID: 1,
		DeliveryID:   d2.ID,
	})

	// We should pick up the delivery error as there has not been a successful delivery since
	// And it's not too old.
	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
		require.Len(t, items[0].AnalysisMessages, 1)
	}

	a1.CreatedAt = sqltime.Time{Time: time.Now().AddDate(-1, 0, 0)}
	db.Save(a1)

	// Now that the associated analysis is older than 1 year, we should ignore the message
	// but still return the analysis
	{
		items, err := as.LatestAnalysesForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		}, true)
		require.NoError(t, err)
		require.Len(t, items, 1)
		require.Len(t, items[0].AnalysisMessages, 0)
	}
}

func TestLatestAnalysesTwoToolsMeansTwoConfigurations(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("CodeQL")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := delivery()
	dbtest.RequireCreate(t, db, d2)

	a2 := analysis(tv2, d2)
	dbtest.RequireCreate(t, db, a2)

	// Since the two tools are different, we should have two different configurations and thus both
	// the two analyses should be returned
	{
		items, err := as.LatestAnalysisIDsForRef(context.Background(), 1, ts.LatestAnalysisFilter{
			Ref: []byte("refs/heads/main"),
		})
		require.NoError(t, err)
		require.Len(t, items, 2)
	}
}

func TestInitialAnalysesForConfigurations(t *testing.T) {
	db := dbtest.RequireConnection(t)
	as := alert.TestService(db)

	t1 := ts.ToolFromCanonicalName("gosec")
	dbtest.RequireCreate(t, db, t1)
	tv1 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t1.ID,
	}
	dbtest.RequireCreate(t, db, tv1)

	d1 := delivery()
	dbtest.RequireCreate(t, db, d1)

	a1 := analysis(tv1, d1)
	dbtest.RequireCreate(t, db, a1)

	t2 := ts.ToolFromCanonicalName("CodeQL")
	dbtest.RequireCreate(t, db, t2)
	tv2 := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  t2.ID,
	}
	dbtest.RequireCreate(t, db, tv2)

	d2 := delivery()
	dbtest.RequireCreate(t, db, d2)

	a2 := analysis(tv2, d2)
	a2.MostRecent = false
	dbtest.RequireCreate(t, db, a2)

	d3 := delivery()
	dbtest.RequireCreate(t, db, d3)

	a3 := analysis(tv2, d3)
	dbtest.RequireCreate(t, db, a3)

	{
		items, err := as.InitialAnalysesForConfigurations(context.Background(), 1, ts.AnalysisFilter{}, []ts.ConfigurationID{a1.ConfigurationID, a3.ConfigurationID})
		require.NoError(t, err)
		require.Len(t, items, 2)
		require.ElementsMatch(
			t,
			transforms.Map(items, func(a ts.Analysis) ts.AnalysisID { return a.ID }),
			[]ts.AnalysisID{a1.ID, a2.ID},
		)
	}
}

func delivery() *ts.Delivery {
	return &ts.Delivery{
		RepositoryID: 1,
		SarifPath:    "example.sarif",
		CommitOid:    ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		Ref:          []byte("refs/heads/main"),
		Failed:       true,
		AnalysisKey:  "key",
		CheckoutURI:  "",
		CheckRunIds:  []uint64{123},
	}
}

func analysis(tv *ts.ToolVersion, d *ts.Delivery) *ts.Analysis {
	return &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Ref:                []byte("refs/heads/main"),
		CommitOid:          ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709"),
		AnalysisKey:        "key",
		ToolID:             tv.ToolID,
		DeliveryID:         d.ID,
		ToolVersionID:      tv.ID,
		ToolVersion:        tv,
		Category:           ts.ToCategory("main"),
		AnalysisComplete:   true,
		MostRecent:         true,
		DeliveryOrigin:     ts.DeliveryOrigin_API,
	}
}

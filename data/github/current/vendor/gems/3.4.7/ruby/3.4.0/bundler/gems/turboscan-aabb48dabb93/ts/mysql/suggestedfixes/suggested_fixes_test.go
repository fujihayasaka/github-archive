package suggestedfixes

import (
	"context"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/proto"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func TestCreateSuggestedFix(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()

	expectedSFA := setupAlerts(t, db, 1, "testing.js", nil)

	require.NoError(t, s.CreateSuggestedFix(ctx, expectedSFA))
	require.NotZero(t, expectedSFA.ID)
	require.NotNil(t, expectedSFA.SuggestedFix)
	require.NotZero(t, expectedSFA.SuggestedFix.ID)
	require.NotZero(t, len(expectedSFA.SuggestedFix.Files))

	dummySFA := setupAlerts(t, db, 2, "main.js", expectedSFA.PhysicalAlert.Analysis)
	dummySFA.SuggestedFix = nil

	require.NoError(t, s.CreateSuggestedFix(ctx, dummySFA))
	require.NotZero(t, dummySFA.ID)
	require.Nil(t, dummySFA.SuggestedFixID)
	require.Nil(t, dummySFA.SuggestedFix)
	require.Equal(t, uint32(2), dummySFA.LogicalAlertNumber)
}

func TestGetSuggestedFix(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()

	// no fix
	sfaID := ts.SuggestedFixAlertID(100)
	sfa, err := s.GetSuggestedFixAlert(ctx, sfaID, nil)
	require.Error(t, err)
	require.Nil(t, sfa)

	expectedSFA := setupAlerts(t, db, 1, "testing.js", nil)
	require.NoError(t, s.CreateSuggestedFix(ctx, expectedSFA))

	sfa, err = s.GetSuggestedFixAlert(ctx, expectedSFA.ID, nil)
	require.NoError(t, err)
	require.NotNil(t, sfa)
	require.Equal(t, expectedSFA.ID, sfa.ID)
}

func TestUpdateSFA(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()

	sfa := setupAlerts(t, db, 1, "testing.js", nil)
	require.NoError(t, s.CreateSuggestedFix(ctx, sfa))

	err := db.First(sfa).Error
	require.NoError(t, err)

	sfa.SetState(ts.SuggestedFixAlertStateApplied, nil)
	err = s.UpdateSFA(ctx, sfa)
	require.NoError(t, err)
}

func TestGetSuggestedFixAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()

	firstSFA := setupAlerts(t, db, 1, "testing.js", nil)
	secondSFA := setupAlerts(t, db, 2, "hello.py", firstSFA.PhysicalAlert.Analysis)
	sfaWithoutFix := setupAlerts(t, db, 3, "main.js", firstSFA.PhysicalAlert.Analysis)
	sfaWithoutFix.SuggestedFix = nil

	require.NoError(t, s.CreateSuggestedFix(ctx, firstSFA))
	require.NoError(t, s.CreateSuggestedFix(ctx, secondSFA))
	require.NoError(t, s.CreateSuggestedFix(ctx, sfaWithoutFix))

	refs := [][]byte{firstSFA.RefBytes}
	logicalNums := []uint32{firstSFA.LogicalAlertNumber, secondSFA.LogicalAlertNumber, sfaWithoutFix.LogicalAlertNumber}
	sfa, err := s.GetSuggestedFixAlerts(ctx, 1, logicalNums, refs)
	require.NoError(t, err)
	require.NotNil(t, sfa[0].SuggestedFix)
	require.Equal(t, 1, len(sfa[0].SuggestedFix.Files))
	require.Equal(t, 3, len(sfa))
	require.Nil(t, sfa[2].SuggestedFix)

	logicalNums = []uint32{}
	sfa, err = s.GetSuggestedFixAlerts(ctx, 1, logicalNums, refs)
	require.NoError(t, err)
	require.Equal(t, 0, len(sfa))
}

func TestFindFindInvalidSuggestedFix(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()

	sfaWithoutFix := setupAlerts(t, db, 2, "main.js", nil)
	sfaWithoutFix.SuggestedFix = nil
	sfaWithoutFix.State = ts.SuggestedFixAlertStateInvalid
	require.NoError(t, s.CreateSuggestedFix(ctx, sfaWithoutFix))

	invalid, err := s.FindInvalidSuggestedFix(ctx, 1, sfaWithoutFix.LogicalAlertNumber)
	require.NoError(t, err)
	require.NotNil(t, invalid)
	require.Nil(t, invalid.SuggestedFix)
}

func TestGetSuggestedFixStatistics(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()

	repoIds := []uint64{1}
	alertNo := 1
	sfa, _ := setupAlertsForStat(t, db, uint32(alertNo), "main.js")
	require.NoError(t, s.CreateSuggestedFix(ctx, sfa))

	now := time.Now()
	start := now.AddDate(0, 0, -1)
	end := now.AddDate(0, 0, 1)

	// no filter, lookup by owner_ids
	ownerIds := []uint64{1}
	filter := StatisticsFilter{OwnerIds: ownerIds, Start: start, End: end}
	res, err := s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// other severity filter should return 0 counter
	// filter by repo_ids
	filter.RepositoryIds = repoIds
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// repo_id mismatch
	filter.RepositoryIds = []uint64{2}
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(0), res.TotalSuggested)

	// filter by rule_ids
	rule_ids := []string{"js/reflected-xss"}
	filter = StatisticsFilter{OwnerIds: ownerIds, Start: start, End: end, RuleIds: rule_ids}
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// rule_id mismatch
	rule_ids = []string{"js/path-injection"}
	filter.RuleIds = rule_ids
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(0), res.TotalSuggested)

	// filter by exclude_rule_ids
	exclude_rule_ids := []string{"js/reflected-xss"}
	filter = StatisticsFilter{OwnerIds: ownerIds, Start: start, End: end, ExcludeRuleIds: exclude_rule_ids}
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(0), res.TotalSuggested)

	// exclude_rule_ids mismatch
	exclude_rule_ids = []string{"js/path-injection"}
	filter.ExcludeRuleIds = exclude_rule_ids
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// filter by severity
	severities := []proto.Severity{proto.Severity_SEVERITY_CRITICAL}
	filter = StatisticsFilter{OwnerIds: ownerIds, Start: start, End: end, Severities: severities}
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// severity mismatch
	severities = append(severities, proto.Severity_SEVERITY_HIGH)
	filter.Severities = severities
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// empty severity should return 1
	severities = []proto.Severity{}
	filter.Severities = severities
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(1), res.TotalSuggested)

	// date filter test
	filter = StatisticsFilter{OwnerIds: ownerIds, Start: end, End: end}
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(0), res.TotalSuggested)

	// SFA without suggested fix
	sfa.SuggestedFix = nil
	sfa.SuggestedFixID = nil
	sfa.State = ts.SuggestedFixAlertStateError
	err = db.Save(sfa).Error
	require.NoError(t, err)
	filter = StatisticsFilter{OwnerIds: ownerIds, Start: start, End: end}
	res, err = s.GetSuggestedFixStatistics(ctx, filter)
	require.NoError(t, err)
	require.Equal(t, uint64(0), res.TotalSuggested)
}

func TestFindSuggestedFixAlertsWithFixes(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := NewService(db)
	ctx := context.Background()
	alertsRef := []byte("/refs/pull/42/merge")

	expectedSFA := setupAlerts(t, db, 1, "testing.js", nil)
	require.NoError(t, s.CreateSuggestedFix(ctx, expectedSFA))
	require.NotNil(t, expectedSFA.SuggestedFix)

	fixes, err := s.FindSuggestedFixAlertsWithFixes(ctx, 1, []uint32{expectedSFA.LogicalAlertNumber, expectedSFA.LogicalAlertNumber + 99}, alertsRef)
	require.NoError(t, err)
	require.Len(t, fixes, 1)

	// Create a new physical alert with the same logical alert number
	dbtest.RequireCount(t, 1, db.Model(&ts.PhysicalAlert{}))
	pa := expectedSFA.PhysicalAlert
	pa.ID = 0
	pa.AnalysisID++
	pa.Analysis = &ts.Analysis{ID: pa.AnalysisID}
	require.NoError(t, db.Create(pa).Error)
	dbtest.RequireCount(t, 2, db.Model(&ts.PhysicalAlert{}))

	stateTime := sqltime.Now()
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:        1,
		LogicalAlertNumber:  expectedSFA.LogicalAlertNumber,
		State:               ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:      stateTime,
		RuleSarifIdentifier: "rule",
		RefBytes:            []byte("refs/heads/main"),
		SuggestedFix:        expectedSFA.SuggestedFix,
		RequestedAt:         stateTime,
	}
	dbtest.RequireCreate(t, db, sfa)

	fixes, err = s.FindSuggestedFixAlertsWithFixes(ctx, 1, []uint32{expectedSFA.LogicalAlertNumber}, alertsRef)
	require.NoError(t, err)
	require.Len(t, fixes, 1)

	// new alert
	sfaWithoutFix := setupAlerts(t, db, 2, "main.js", expectedSFA.PhysicalAlert.Analysis)
	require.NoError(t, s.CreateSuggestedFix(ctx, sfaWithoutFix))
	fixes, err = s.FindSuggestedFixAlertsWithFixes(ctx, 1, []uint32{1, 2}, alertsRef)
	require.NoError(t, err)
	require.Len(t, fixes, 2)

	// invalidate the fix
	db.Model(&ts.SuggestedFixAlert{}).Where("logical_alert_number = ?", 2).Updates(
		map[string]interface{}{"suggested_fix_id": nil,
			"state": ts.SuggestedFixAlertStateInvalid,
		})

	// double check there is only one sfa without sf
	var count int
	db.Model(&ts.SuggestedFixAlert{}).Where("suggested_fix_id is null").Count(&count)
	require.Equal(t, 1, count)

	fixes, err = s.FindSuggestedFixAlertsWithFixes(ctx, 1, []uint32{1, 2}, alertsRef)
	require.NoError(t, err)
	require.Len(t, fixes, 1)
	require.Equal(t, uint32(1), fixes[0].LogicalAlertNumber)
}

func setupAlerts(t *testing.T, db *gorm.DB, number uint32, filePath string, analysis *ts.Analysis) *ts.SuggestedFixAlert {
	t.Helper()
	ref := []byte("/refs/pull/42/merge")

	if analysis == nil {
		analysis = &ts.Analysis{
			CommitOid:          "xxx",
			Ref:                ref,
			RepositoryID:       1,
			SourceRepositoryID: 1,
			MostRecent:         true,
			AnalysisComplete:   true,
		}
		dbtest.RequireCreate(t, db, analysis)
	}

	la := &ts.LogicalAlert{
		Number:                number,
		RepositoryID:          1,
		StableAlertIdentifier: []byte(filePath),
		FilePath:              filePath,
	}
	require.NoError(t, db.Create(la).Error)
	actual := &ts.LogicalAlert{}
	db.Where("number = ?", la.Number).First(actual)
	require.Equal(t, la.Number, actual.Number)

	now := sqltime.Now()
	pa := &ts.PhysicalAlert{
		RepositoryID:          1,
		AnalysisID:            analysis.ID,
		LogicalAlertID:        la.ID,
		StableAlertIdentifier: []byte(filePath),
		LastStateChangeAt:     now,
	}
	require.NoError(t, db.Create(pa).Error)
	actual_pa := &ts.PhysicalAlert{}
	db.Where("id = ?", pa.ID).First(actual_pa)
	require.Equal(t, pa.AnalysisID, actual_pa.AnalysisID)

	pa.LogicalAlert = la
	pa.Analysis = analysis

	sf := &ts.SuggestedFix{
		RepositoryID: 1,
		Description:  "test",
		AiVersion:    "test",
		AiModel:      "test",
	}
	stateTime := sqltime.Now()
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:        1,
		LogicalAlertNumber:  la.Number,
		State:               ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:      stateTime,
		RuleSarifIdentifier: "rule",
		RefBytes:            ref,
		RequestedAt:         stateTime,
	}
	files := []*ts.SuggestedFixFile{
		{
			RepositoryID: 1,
			FilePath:     filePath,
			FileChecksum: ts.BuildFileChecksum([]byte("beef")),
			DiffContent:  []byte("test"),
		},
	}

	sf.Files = files
	sfa.SuggestedFix = sf
	sfa.PhysicalAlert = pa

	return sfa
}

func setupAlertsForStat(t *testing.T, db *gorm.DB, number uint32, filePath string) (*ts.SuggestedFixAlert, *ts.PhysicalAlert) {
	t.Helper()

	now := sqltime.Now()
	dbtest.RequireCreate(t, db, &ts.Repository{
		OwnerID:         1,
		RepositoryID:    1,
		SourceUpdatedAt: now,
		DefaultRef:      []byte("main"),
	})

	globalTool := &ts.Tool{
		ID:            123,
		CanonicalName: "ABC",
	}

	sarifId := "js/reflected-xss"
	rule := &ts.Rule{
		ID:              1,
		ToolID:          globalTool.ID,
		SarifIdentifier: sarifId,
	}
	rule.SetTags([]string{"red"})
	dbtest.RequireCreate(t, db, rule)

	laNo := 1
	sfa := setupAlerts(t, db, uint32(laNo), "main.js", nil)
	sfa.RuleSarifIdentifier = sarifId
	pa := sfa.PhysicalAlert
	severity := 10.
	pa.SecuritySeverity = &severity // critical
	pa.RuleID = rule.ID
	db.Save(pa)

	la := &ts.LogicalAlert{}
	db.Where("number = ?", laNo).First(la)
	la.SecuritySeverity = pa.SecuritySeverity
	la.SeverityLevel = pa.SeverityLevel
	db.Save(la)

	a := pa.Analysis

	a.MostRecent = false
	db.Save(a)

	// mark the alert as fixed in new analysis
	na := a
	na.ID = 0
	na.MostRecent = true
	na.BaselineID = &a.ID
	require.NoError(t, db.Create(na).Error)

	fixedA := sfa.PhysicalAlert.DeepCopy()
	fixedA.ID = 0
	fixedA.Analysis = na
	fixedA.AnalysisID = na.ID
	fixedA.IsFixed = true
	fixedA.LastSeenAnalysisID = &a.ID
	fixedA.LastSeenAnalysis = a
	require.NoError(t, db.Create(fixedA).Error)
	require.NotZero(t, fixedA.ID)
	require.NotEqual(t, pa.ID, fixedA.ID)

	pas := []*ts.PhysicalAlert{}
	err := db.Model(ts.PhysicalAlert{}).Preload("LogicalAlert").Find(&pas).Error
	require.NoError(t, err)
	require.Len(t, pas, 2)
	for _, pa := range pas {
		require.Equal(t, uint32(laNo), pa.LogicalAlert.Number)
		if pa.IsFixed {
			// last seen analysis id should points to previous alert
			require.Equal(t, &a.ID, pa.LastSeenAnalysisID)
		}
	}
	return sfa, fixedA
}

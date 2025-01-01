package publishers

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/golang/protobuf/ptypes/timestamp"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	insightshydro "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	insightshydroentities "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mocks"
)

func TestNewInsightsEntityBatchEvent(t *testing.T) {
	ctx, publisher, handler, db := setupInsightsAlertHandlerTests(t)

	event_time := time.Now().UTC()

	logicalAlertId := 18
	physicalAlertId := 25
	alertNumber := 101

	la, _ := setupTestDataForESToLogicalAlertsMapping(t, db, 1, logicalAlertId, physicalAlertId, alertNumber)

	searchDocs, err := ts.SearchDocumentsFromAlerts(&ts.Repository{ID: 1}, []*ts.LogicalAlert{la})
	require.NoError(t, err)

	searchDoc := searchDocs[0]

	insightsData := handler.GetAlertFieldsHash(ctx, searchDoc, event_time)
	require.NoError(t, err)
	expected := &insightshydro.InsightsEntityBatch{
		Entity:          InsightsAlertEntityName,
		EntitiesUpdated: []*insightshydroentities.InsightsData{insightsData},
	}

	docs := []*ts.SearchDocument{}
	expected1 := &insightshydro.InsightsEntityBatch{Entity: InsightsAlertEntityName}
	expected2 := &insightshydro.InsightsEntityBatch{Entity: InsightsAlertEntityName}
	for i := 0; i < entityEventsPageSize; i++ {
		docs = append(docs, searchDoc)
		docs = append(docs, searchDoc)
		expected1.EntitiesUpdated = append(expected1.EntitiesUpdated, insightsData)
		expected2.EntitiesUpdated = append(expected2.EntitiesUpdated, insightsData)
	}

	single := publisher.EXPECT().
		InsightsEntityBatchEvent(gomock.Any(), expected).
		Return(nil).
		Times(1)

	batch := publisher.EXPECT().
		InsightsEntityBatchEvent(gomock.Any(), expected1).
		Return(nil).
		Times(2)

	gomock.InOrder(single, batch)

	// Test single alert
	err = handler.NewInsightsEntityBatchEvent(ctx, []*ts.SearchDocument{searchDoc}, event_time)
	require.NoError(t, err)

	// Test paging
	err = handler.NewInsightsEntityBatchEvent(ctx, docs, event_time)
	require.NoError(t, err)
}

func TestGetAlertFieldsHash(t *testing.T) {
	ctx, _, handler, db := setupInsightsAlertHandlerTests(t)

	trueVar := true
	falseVar := false
	event_time := time.Now().Add(time.Hour * 10)
	logicalAlertId := 18
	physicalAlertId := 25
	alertNumber := 101

	setupTestDataForESToLogicalAlertsMapping(t, db, 1, logicalAlertId, physicalAlertId, alertNumber)

	fixedAfterResolvedDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		ResolvedAt:        &sqltime.Time{Time: time.Now().Add(time.Hour * 2)},
		FixedAt:           &sqltime.Time{Time: time.Now().Add(time.Hour * 3)},
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
		AutofixState:      "",
	}

	expected := &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             fixedAfterResolvedDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             fixedAfterResolvedDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              convertToTimestampPrecision(fixedAfterResolvedDoc.FixedAt),
			"closed":                 "true",
			"present_on_default_ref": "false",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "false",
			"autofix_accepted":       "false",
		},
	}
	insightsData := handler.GetAlertFieldsHash(ctx, fixedAfterResolvedDoc, event_time)
	require.Equal(t, expected, insightsData)

	resolvedAfterFixedDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		ResolvedAt:        &sqltime.Time{Time: time.Now().Add(time.Hour * 2)},
		Resolved:          &trueVar,
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
	}

	expected = &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             resolvedAfterFixedDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             resolvedAfterFixedDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              convertToTimestampPrecision(resolvedAfterFixedDoc.ResolvedAt),
			"closed":                 "true",
			"present_on_default_ref": "false",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "false",
			"autofix_accepted":       "false",
		},
	}
	insightsData = handler.GetAlertFieldsHash(ctx, resolvedAfterFixedDoc, event_time)
	require.Equal(t, expected, insightsData)

	fixedOnDefaultDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		FixedOnDefault:    &trueVar,
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
	}

	expected = &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             fixedOnDefaultDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             fixedOnDefaultDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              "",
			"closed":                 "true",
			"present_on_default_ref": "true",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "false",
			"autofix_accepted":       "false",
		},
	}
	insightsData = handler.GetAlertFieldsHash(ctx, fixedOnDefaultDoc, event_time)
	require.Equal(t, expected, insightsData)

	notFixedOnDefaultDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		FixedOnDefault:    &falseVar,
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
	}

	expected = &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             notFixedOnDefaultDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             notFixedOnDefaultDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              "",
			"closed":                 "false",
			"present_on_default_ref": "true",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "false",
			"autofix_accepted":       "false",
		},
	}
	insightsData = handler.GetAlertFieldsHash(ctx, notFixedOnDefaultDoc, event_time)
	require.Equal(t, expected, insightsData)
}

func TestAlertStates(t *testing.T) {
	ctx, _, handler, db := setupInsightsAlertHandlerTests(t)

	trueVar := true
	falseVar := false
	event_time := time.Now().Add(time.Hour * 10)
	logicalAlertId := 18
	physicalAlertId := 25
	alertNumber := 101

	setupTestDataForESToLogicalAlertsMapping(t, db, 1, logicalAlertId, physicalAlertId, alertNumber)

	// Autofix has a valid state
	fixedAfterResolvedDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		ResolvedAt:        &sqltime.Time{Time: time.Now().Add(time.Hour * 2)},
		FixedAt:           &sqltime.Time{Time: time.Now().Add(time.Hour * 3)},
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
		AutofixState:      "valid",
	}

	expected := &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             fixedAfterResolvedDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             fixedAfterResolvedDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              convertToTimestampPrecision(fixedAfterResolvedDoc.FixedAt),
			"closed":                 "true",
			"present_on_default_ref": "false",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "true",
			"autofix_accepted":       "false",
		},
	}
	insightsData := handler.GetAlertFieldsHash(ctx, fixedAfterResolvedDoc, event_time)
	require.Equal(t, expected, insightsData)

	// Autofix has a valid_missing_dep state
	resolvedAfterFixedDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		ResolvedAt:        &sqltime.Time{Time: time.Now().Add(time.Hour * 2)},
		Resolved:          &trueVar,
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
		AutofixState:      "valid_missing_dep",
	}

	expected = &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             resolvedAfterFixedDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             resolvedAfterFixedDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              convertToTimestampPrecision(resolvedAfterFixedDoc.ResolvedAt),
			"closed":                 "true",
			"present_on_default_ref": "false",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "true",
			"autofix_accepted":       "false",
		},
	}
	insightsData = handler.GetAlertFieldsHash(ctx, resolvedAfterFixedDoc, event_time)
	require.Equal(t, expected, insightsData)

	// Autofix has an invalid state
	fixedOnDefaultDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		FixedOnDefault:    &trueVar,
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
		AutofixState:      "invalid",
	}

	expected = &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             fixedOnDefaultDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             fixedOnDefaultDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              "",
			"closed":                 "true",
			"present_on_default_ref": "true",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "false",
			"autofix_accepted":       "false",
		},
	}
	insightsData = handler.GetAlertFieldsHash(ctx, fixedOnDefaultDoc, event_time)
	require.Equal(t, expected, insightsData)

	// Autofix has an error state
	notFixedOnDefaultDoc := &ts.SearchDocument{
		AlertID:           uint64(logicalAlertId),
		Number:            uint32(alertNumber),
		RepositoryID:      "1",
		CreatedAt:         &sqltime.Time{Time: time.Now()},
		UpdatedAt:         &sqltime.Time{Time: time.Now().Add(time.Hour)},
		InsightsUpdatedAt: &sqltime.Time{Time: time.Now().Add(time.Hour)},
		FixedOnDefault:    &falseVar,
		RuleName:          "foo",
		SarifIdentifier:   "bar",
		Resolution:        "AlertResolutionNone",
		Tool:              "tool",
		Severity:          "HIGH",
		CanonicalID:       strconv.FormatUint(uint64(physicalAlertId), 10),
		AutofixState:      "error",
	}

	expected = &insightshydroentities.InsightsData{
		Data: map[string]string{
			"id":                     "18",
			"repository_id":          "1",
			"created_at":             notFixedOnDefaultDoc.CreatedAt.Format(time.RFC3339Nano),
			"updated_at":             notFixedOnDefaultDoc.InsightsUpdatedAt.Format(time.RFC3339Nano),
			"resolution":             "0",
			"rule_name":              "foo",
			"rule_sarif_identifier":  "bar",
			"tool_name":              "tool",
			"severity":               "3",
			"closed_at":              "",
			"closed":                 "false",
			"present_on_default_ref": "true",
			"source_time":            event_time.Format(time.RFC3339Nano),
			"number":                 strconv.FormatUint(uint64(alertNumber), 10),
			"has_autofix":            "false",
			"autofix_accepted":       "false",
		},
	}
	insightsData = handler.GetAlertFieldsHash(ctx, notFixedOnDefaultDoc, event_time)
	require.Equal(t, expected, insightsData)
}

func convertToTimestampPrecision(datetime *sqltime.Time) string {
	return (&timestamp.Timestamp{Seconds: datetime.Unix(), Nanos: int32(datetime.Nanosecond())}).AsTime().Format(time.RFC3339Nano)
}

func setupInsightsAlertHandlerTests(t *testing.T) (
	context.Context,
	*mocks.MockInsightsPublisher,
	ts.InsightsHydroAlertEventHandler,
	*gorm.DB,
) {
	t.Helper()
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	alertService := alert.TestService(db)
	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockInsightsPublisher(mockCtrl)
	handler := NewInsightsHydroAlertHandler(publisher, alertService)

	return ctx, publisher, handler, db
}

func setupTestDataForESToLogicalAlertsMapping(t *testing.T, db *gorm.DB, repoId int, logicalAlertId int, physicalAlertId int, alertNumber int) (
	*ts.LogicalAlert,
	*ts.PhysicalAlert,
) {
	t.Helper()
	commit := "da39a3ee5e6b4b0d3255bfef95601890afd80709"
	repoID := ts.RepositoryEID(repoId)
	analysis := setupFirstAnalysis(t, db, repoID, commit)
	rule1 := &ts.Rule{
		Name:             "Rule1",
		ShortDescription: "Rule 1",
		FullDescription:  "This is Rule 1",
		SeverityLevel:    ts.SeverityLevelError,
		SarifIdentifier:  "js/one",
	}
	rule1.SetTags([]string{"rule1"})
	dbtest.RequireCreate(t, db, rule1)

	// Create a different analysis
	analysis = createAnalysis(t, db, repoID, analysis.ToolVersion, commit, "js2")
	return createNewAlertCombo(t, db, analysis, rule1, logicalAlertId, physicalAlertId, uint8(alertNumber))
}

func setupFirstAnalysis(t *testing.T, db *gorm.DB, repoID ts.RepositoryEID, commit string) *ts.Analysis {
	t.Helper()
	tool := &ts.Tool{
		CanonicalName:  "CodeQL",
		GUID:           "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, tool)
	toolVersion := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  tool.ID,
	}
	dbtest.RequireCreate(t, db, toolVersion)

	return createAnalysis(t, db, repoID, toolVersion, commit, "js1")
}

func createNewAlertCombo(t *testing.T, db *gorm.DB, analysis *ts.Analysis, rule1 *ts.Rule, logicalAlertId int, physicalAlertId int, alertNumber uint8) (
	*ts.LogicalAlert,
	*ts.PhysicalAlert,
) {
	t.Helper()
	p1 := &ts.PhysicalAlert{
		ID:                  ts.PhysicalAlertID(physicalAlertId),
		RuleSarifIdentifier: rule1.SarifIdentifier,
		SeverityLevel:       rule1.SeverityLevel,
		Fingerprint:         "fp1",
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		LogicalAlertID:        ts.LogicalAlertID(logicalAlertId),
		StableAlertIdentifier: []byte{alertNumber},
		AnalysisID:            analysis.ID,
		RepositoryID:          analysis.RepositoryID,
		LastStateChangeAt:     sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, p1)
	a1 := &ts.LogicalAlert{
		ID:                    ts.LogicalAlertID(logicalAlertId),
		RuleID:                rule1.ID,
		Number:                uint32(alertNumber),
		StableAlertIdentifier: []byte{alertNumber},
		RepositoryID:          analysis.RepositoryID,
		SarifIdentifier:       rule1.SarifIdentifier,
		Message:               "message",
		FilePath:              "src/file1",
		PhysicalAlerts:        []*ts.PhysicalAlert{p1},
	}
	dbtest.RequireCreate(t, db, a1)
	return a1, p1
}

func createAnalysis(t *testing.T, db *gorm.DB, repoID ts.RepositoryEID, tv *ts.ToolVersion, commit, category string) (analysis *ts.Analysis) {
	t.Helper()
	analysis = &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          ts.ToSha(commit),
		ToolID:             tv.ToolID,
		ToolVersionID:      tv.ID,
		ToolVersion:        tv,
		Category:           ts.ToCategory(category),
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis)

	return
}

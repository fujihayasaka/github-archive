package mysql

import (
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

// Test read/write for LogicalAlert
func TestLogicalAlert(t *testing.T) {
	db := dbtest.RequireConnection(t)

	now := sqltime.Now()
	resolverID := ts.UserEID(13)
	expected := &ts.LogicalAlert{
		RepositoryID:          66,
		Number:                7,
		RuleID:                ts.RuleID(98),
		Resolution:            ts.AlertResolutionFalsePositive,
		ResolverID:            &resolverID,
		ResolvedAt:            &now,
		Weight:                160,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		FilePath:              "test/my/file.js",
		Region: ts.Region{
			StartLine:   23,
			EndLine:     56,
			StartColumn: 2,
			EndColumn:   67,
		},
		Message:            "Variable x is not used",
		FileClassification: ts.FileClassification{"generated"},
	}
	require.NoError(t, db.Create(expected).Error)
	actual := &ts.LogicalAlert{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)

	db.LogMode(false) // Disable logging since this will yield an error
	invalid := &ts.LogicalAlert{
		RepositoryID: 66,
		Number:       8,
		RuleID:       ts.RuleID(98),
		Resolution:   11,
		ResolverID:   &resolverID,
		ResolvedAt:   &now,
		Weight:       0,
		FilePath:     "test/my/file.js",
		Region: ts.Region{
			StartLine:   23,
			EndLine:     56,
			StartColumn: 2,
			EndColumn:   67,
		},
		Message:            "Variable x is not used",
		FileClassification: ts.FileClassification{"generated"},
	}
	require.Error(t, db.Create(invalid).Error)

	expected = &ts.LogicalAlert{
		RepositoryID:          66,
		Number:                9,
		RuleID:                ts.RuleID(98),
		Resolution:            ts.AlertResolutionFalsePositive,
		ResolverID:            nil,
		ResolvedAt:            nil,
		Weight:                190,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2},
		FilePath:              "test/my/file.js",
		Region: ts.Region{
			StartLine:   23,
			EndLine:     56,
			StartColumn: 2,
			EndColumn:   67,
		},
		Message:            "Variable x is not used",
		FileClassification: ts.FileClassification{"generated"},
	}
	require.NoError(t, db.Create(expected).Error)
	actual = &ts.LogicalAlert{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)
}

func TestPhysicalAlert(t *testing.T) {
	db := dbtest.RequireConnection(t)

	expected := &ts.PhysicalAlert{
		RepositoryID:   66,
		LogicalAlertID: ts.LogicalAlertID(23),
		RuleID:         ts.RuleID(12),
		Fingerprint:    "abc",
		FilePath:       "test/my/file.js",
		Region: ts.Region{
			StartLine:   23,
			EndLine:     56,
			StartColumn: 2,
			EndColumn:   67,
		},
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
		Suppressed:            true,
		Message:               "Variable x is not used",
		AnalysisID:            ts.AnalysisID(94),
		FileClassification:    ts.FileClassification{"generated"},
		LastStateChangeAt:     sqltime.Now(),
	}
	require.NoError(t, db.Create(expected).Error)
	actual := &ts.PhysicalAlert{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)
}

func TestTimelineEvent(t *testing.T) {
	db := dbtest.RequireConnection(t)

	expected := &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 23,
		EventType:      ts.TimelineEventTypeAlertAppearedInBranch,
		CommitOid:      "12345676890abcdef123",
		Ref:            "/ref/blah",
		FilePath:       "src/lol/really_long_directory_to_get/to_the_file/fetch.js",
		StartLine:      42,
		ToolVersionID:  123,
		Environment:    make(map[string]string),
		WorkflowRunID:  101,
		EventTimestamp: sqltime.Now(),
	}
	require.NoError(t, db.Create(expected).Error)
	actual := &ts.TimelineEvent{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)

	user := ts.UserEID(1234)
	expected = &ts.TimelineEvent{
		RepositoryID:   1,
		LogicalAlertID: 24,
		EventType:      ts.TimelineEventTypeAlertResolvedByUser,
		UserID:         &user,
		Resolution:     ts.AlertResolutionWontFix,
		Environment:    make(map[string]string),
		WorkflowRunID:  101,
		EventTimestamp: sqltime.Now(),
	}
	require.NoError(t, db.Create(expected).Error)
	actual = &ts.TimelineEvent{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)

}

func TestAnalysis(t *testing.T) {
	db := dbtest.RequireConnection(t)

	repoID := ts.RepositoryEID(234)
	expected := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		CommitOid:          ".github/workflows/main.yml",
		Ref:                []byte("main"),
		AnalysisName:       "my-project",
		ToolID:             123,
		ToolVersionID:      234,
		Environment:        ts.AnalysisEnv{},
		WorkflowRunID:      101,
		Failed:             true,
		AnalysisComplete:   true,
	}
	require.NoError(t, db.Create(expected).Error)
	actual := &ts.Analysis{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)

	// Cannot update existing row to invalid state (failed AND most recent)
	actual.MostRecent = true
	require.Error(t, db.Save(actual).Error)

	// Cannot create most recent analysis that failed
	require.Error(t, db.Create(&ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Failed:             true,
		AnalysisComplete:   true,
		MostRecent:         true,
	}).Error)

	// Cannot create most recent analysis that is incomplete
	require.Error(t, db.Create(&ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		MostRecent:         true,
	}).Error)

	// Cannot create failed analysis that is incomplete
	require.Error(t, db.Create(&ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Failed:             true,
	}).Error)
}

func TestRule(t *testing.T) {
	db := dbtest.RequireConnection(t)
	require.NotNil(t, db)

	expected := &ts.Rule{
		ToolID:           1234,
		SarifIdentifier:  "py/multiple-definition",
		Name:             "Variable defined multiple times",
		ShortDescription: "Assignment to a variable occurs multiple times without any intermediate use of that variable",
		FullDescription:  "Very long description [...]",
		HelpURI:          "https://lgtm.com/rules/1800095/",
		Help:             "Don't do this",
		SeverityLevel:    ts.SeverityLevelError,
		PrecisionLevel:   ts.PrecisionLevelHigh,
	}
	dbtest.RequireCreate(t, db, expected)
	actual := &ts.Rule{}
	err := db.Where("id = ?", expected.ID).First(actual).Error
	require.NoError(t, err)
	require.Equal(t, expected, actual)

	// Load Tags
	tag := &ts.RuleTag{
		RuleID: expected.ID,
		Tag:    "red",
	}
	dbtest.RequireCreate(t, db, tag)
	err = db.Where("id = ?", expected.ID).First(&actual).Error
	require.NoError(t, err)
	require.Nil(t, actual.Tags)

	err = db.Where("id = ?", expected.ID).Preload("Tags").First(&actual).Error
	require.NoError(t, err)
	require.Len(t, actual.Tags, 1)
	require.Equal(t, "red", actual.Tags[0].Tag)
}

func TestRuleGetTags(t *testing.T) {
	ruleWNil := &ts.Rule{
		ID:   1,
		Tags: nil,
	}
	ruleWEmpty := &ts.Rule{
		ID:   1,
		Tags: []ts.RuleTag{},
	}
	ruleWValues := &ts.Rule{
		ID: 1,
		Tags: []ts.RuleTag{
			{Tag: "red"},
		},
	}

	_, err := ruleWNil.GetTags()
	require.Error(t, err)

	tags, err := ruleWEmpty.GetTags()
	require.NoError(t, err)
	require.Empty(t, tags)

	tags, err = ruleWValues.GetTags()
	require.NoError(t, err)
	require.Len(t, tags, 1)
	require.Equal(t, "red", tags[0])
}

func TestRuleHasTags(t *testing.T) {
	rule := &ts.Rule{
		Tags: []ts.RuleTag{
			{Tag: "red"},
			{Tag: "blu"},
		},
	}

	require.True(t, rule.HasTag("blu"))
	require.False(t, rule.HasTag("green"))
}

func TestRuleTagSetBehavior(t *testing.T) {
	db := dbtest.RequireConnection(t)

	rule := &ts.Rule{}
	rule.SetTags([]string{"red", "red"})
	dbtest.RequireCreate(t, db, rule)
	dbtest.RequireCount(t, 1, db.Model(&ts.RuleTag{}).Where(ts.RuleTag{RuleID: rule.ID}))
}

func TestRuleValidation(t *testing.T) {
	db := dbtest.RequireConnection(t)

	expected := &ts.Rule{
		SeverityLevel: 11,
	}

	db.LogMode(false) // Disable logging since this will yield an error
	err := db.Create(expected).Error
	require.Error(t, err, "Invalid value '11' for SeverityLevel")

	// Fix and create
	expected.SeverityLevel = ts.SeverityLevelError
	require.NoError(t, db.Create(expected).Error)

	// Corrupt the DB
	err = db.Exec("UPDATE ts_rules SET severity_level = 11 WHERE id = ?", expected.ID).Error
	require.NoError(t, err)

	actual := &ts.Rule{}
	err = db.Where("id = ?", expected.ID).First(actual).Error
	require.Error(t, err, "Invalid value '11' for SeverityLevel")
}

func TestAutogeneratedFieldsInBaseModel(t *testing.T) {
	db := dbtest.RequireConnection(t)
	require.NotNil(t, db)

	object := &ts.LogicalAlert{
		RepositoryID:          66,
		Number:                7,
		RuleID:                98,
		StableAlertIdentifier: []byte{1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1},
	}

	require.NoError(t, db.Create(object).Error)
	require.NotZero(t, object.ID)
	require.NotZero(t, object.CreatedAt)
	require.NotZero(t, object.UpdatedAt)
}

func TestSuggestedFix(t *testing.T) {
	db := dbtest.RequireConnection(t)

	expected := &ts.SuggestedFix{
		RepositoryID: 1,
		Description:  "Example",
		AiVersion:    "1.0.0",
		AiModel:      "model",
	}
	require.NoError(t, db.Create(expected).Error)
	actual := &ts.SuggestedFix{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)
}

func TestSuggestedFixAlert(t *testing.T) {
	db := dbtest.RequireConnection(t)
	sfId := ts.SuggestedFixID(1)
	stateUpdatedAt := sqltime.Now()
	expected := &ts.SuggestedFixAlert{
		RepositoryID:        1,
		LogicalAlertNumber:  1,
		SuggestedFixID:      &sfId,
		State:               ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:      stateUpdatedAt,
		RuleSarifIdentifier: "rule",
		RefBytes:            []byte("refs/heads/main"),
		RequestedAt:         sqltime.Now(),
	}

	require.NoError(t, db.Create(expected).Error)
	actual := &ts.SuggestedFixAlert{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)
}

func TestSuggestedFixFile(t *testing.T) {
	db := dbtest.RequireConnection(t)

	expected := &ts.SuggestedFixFile{
		RepositoryID:   1,
		SuggestedFixID: 1,
		FilePath:       "test/my/file.js",
		FilePathHash:   ts.BuildFilePathHash("test/my/file.js"),
		FileChecksum:   ts.BuildFileChecksum([]byte("foobar")),
		DiffContent:    []byte("diff --git a/test/my/file.js b/test/my/file.js\nindex 1234567..abcdefg 100644\n--- a/test/my/file.js\n+++ b/test/my/file.js\n@@ -1,2 +1,2 @@\n-  console.log('hello world');\n+  console.log('hello world!');\n"),
	}
	require.NoError(t, db.Create(expected).Error)
	actual := &ts.SuggestedFixFile{}
	db.Where("id = ?", expected.ID).First(actual)
	require.Equal(t, expected, actual)
}

func TestSuggestedFixAssociations(t *testing.T) {
	db := dbtest.RequireConnection(t)

	fix := &ts.SuggestedFix{
		RepositoryID: 1,
		Description:  "Example",
		AiVersion:    "1.0.0",
		AiModel:      "model",
	}
	require.NoError(t, db.Create(fix).Error)
	stateUpdatedAt := sqltime.Now()
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:        1,
		LogicalAlertNumber:  1,
		SuggestedFixID:      &fix.ID,
		State:               ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:      stateUpdatedAt,
		RuleSarifIdentifier: "rule",
		RefBytes:            []byte("refs/heads/main"),
		RequestedAt:         sqltime.Now(),
	}
	require.NoError(t, db.Create(sfa).Error)

	sff := &ts.SuggestedFixFile{
		RepositoryID:   1,
		SuggestedFixID: fix.ID,
		FilePath:       "test/my/file.js",
		FilePathHash:   ts.BuildFilePathHash("test/my/file.js"),
		FileChecksum:   ts.BuildFileChecksum([]byte("foobar")),
		DiffContent:    []byte("diff --git a/test/my/file.js b/test/my/file.js\nindex 1234567..abcdefg 100644\n--- a/test/my/file.js\n+++ b/test/my/file.js\n@@ -1,2 +1,2 @@\n-  console.log('hello world');\n+  console.log('hello world!');\n"),
	}
	require.NoError(t, db.Create(sff).Error)

	// load all associations
	actual := &ts.SuggestedFix{}
	db.Preload("Alerts").Preload("Files").Where("id = ?", fix.ID).First(actual)
	require.Equal(t, fix.ID, actual.ID)
	require.Len(t, actual.Alerts, 1)
	require.Equal(t, sfa, actual.Alerts[0])
	require.Len(t, actual.Files, 1)
	require.Equal(t, sff, actual.Files[0])
}

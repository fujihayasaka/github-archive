package ts_test

import (
	"context"
	"reflect"
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/workflows"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/slices"
)

func TestSetUpForValidation_OnboardingStateChange(t *testing.T) {
	wt := workflows.NewLibrary().GetWorkflowTemplate(context.Background(), 0)
	c := &ts.CodeqlConfig{}
	run, err := c.SetUpForValidationRun([]byte(""), "", wt, ts.CodeqlRunTriggeringEvent_VALIDATION, 0, ts.CodeqlPacks(""))
	require.NoError(t, err)

	require.True(t, c.IsStaged())
	require.Equal(t, ts.CodeqlRunType_VALIDATION, run.RunType)
	require.NotEmpty(t, c.Workflow)
	require.Equal(t, "v32", c.TemplateVersion) // Ensure that the template version is updated to Latest
}

func TestEmptyTemplate(t *testing.T) {
	wt := &workflows.WorkflowTemplate{}
	c := &ts.CodeqlConfig{}

	_, err := c.SetUpForValidationRun([]byte(""), "", wt, ts.CodeqlRunTriggeringEvent_VALIDATION, 0, ts.CodeqlPacks(""))
	require.Error(t, err)
}

func TestQuerySuite(t *testing.T) {
	c := &ts.CodeqlConfig{}

	qs := c.QuerySuiteType.Root()
	require.Equal(t, ts.QuerySuite_DEFAULT, qs)

	mp := make(map[string]ts.QuerySuite)
	mp["root"] = ts.QuerySuite_EXTENDED
	c = &ts.CodeqlConfig{QuerySuiteType: mp}

	qs = c.QuerySuiteType.Root()
	require.Equal(t, ts.QuerySuite_EXTENDED, qs)
}

// testConfigB is a configuration that includes non-zero values for all "relevant" fields.
// this is used in the TestIsEquivalent test.
func testConfigB() *ts.CodeqlConfig {
	return &ts.CodeqlConfig{
		RepositoryID:            2,
		RepositoryGRID:          "def",
		InitialLanguages:        []string{"ruby", "java-kotlin"},
		Languages:               []string{"ruby"},
		QuerySuiteType:          ts.ExtendedQuerySuiteType(),
		ThreatModel:             ts.ThreatModel_REMOTE_LOCAL,
		UsingCombinedLanguages:  true,
		UsingCSRunnerLabel:      true,
		JavaExtractionOptions:   ts.JavaExtractionOptions_BUILDLESS,
		CSharpExtractionOptions: ts.CSharpExtractionOptions_BUILDLESS,
		RunnerLabel:             "not-code-scanning",
	}
}

func TestIsEquivalent(t *testing.T) {
	// The following fields are not considered when comparing two CodeqlConfig structs:
	ignore := []string{
		"BaseModel", "ID",
		"ValidationRunStatus", "DeprecatedAt", "EnabledAt",
		"OnboardedByActorGRID", "CreatedByActorLogin", "CreatedByActorLogin",
		"ValidationRun", "LatestRun",
		"Workflow", "TemplateVersion", "Tag",
	}
	compared := []string{
		"RepositoryID", "RepositoryGRID",
		"InitialLanguages",
		"Languages", "QuerySuiteType", "ThreatModel",
		"UsingCombinedLanguages", "UsingCSRunnerLabel",
		"JavaExtractionOptions", "CSharpExtractionOptions",
		"RunnerLabel",
	}

	// Check that all fields belong to one of the two categories
	ccType := reflect.TypeOf(ts.CodeqlConfig{})
	for i := 0; i < ccType.NumField(); i++ {
		ccType := reflect.TypeOf(ts.CodeqlConfig{})
		if slices.Contains(ignore, ccType.Field(i).Name) {
			continue
		}
		require.True(t, slices.Contains(compared, ccType.Field(i).Name), ccType.Field(i).Name)
	}

	// Check with 2 example configurations. configA and configB should have
	// different values for all relevant fields.
	configA := ts.CodeqlConfig{
		RepositoryID:            1,
		RepositoryGRID:          "abc",
		Languages:               []string{"python"},
		QuerySuiteType:          ts.DefaultQuerySuiteType(),
		ThreatModel:             ts.ThreatModel_REMOTE,
		UsingCombinedLanguages:  false,
		UsingCSRunnerLabel:      false,
		JavaExtractionOptions:   ts.JavaExtractionOptions_TRACED,
		CSharpExtractionOptions: ts.CSharpExtractionOptions_TRACED,
		RunnerLabel:             "code-scanning",
	}
	require.True(t, configA.IsEquivalent(&configA))

	// Test that testConfigB has interesting values
	configB := testConfigB()
	for _, field := range compared {
		targetValue := reflect.ValueOf(configB).Elem().FieldByName(field).Interface()
		require.NotEqual(t, reflect.Zero(reflect.TypeOf(targetValue)).Interface(), targetValue, field)
	}
	require.True(t, configB.IsEquivalent(configB))

	// The two configs are different
	require.False(t, configA.IsEquivalent(configB))

	// Actually check all these fields are meaningful
	// Every loop we change a single field value using the values from configB. This makes testConfig and configA "not equivalent"
	for _, field := range compared {
		testConfig := configB.CopyForUpdate()
		targetField := reflect.ValueOf(testConfig).Elem().FieldByName(field)
		targetValue := reflect.ValueOf(&configA).Elem().FieldByName(field).Interface()
		targetField.Set(reflect.ValueOf(targetValue))
		require.False(t, testConfig.IsEquivalent(configB), field)
	}
}

func TestCopyForUpdate(t *testing.T) {
	config := testConfigB().CopyForUpdate()
	require.True(t, config.IsEquivalent(testConfigB()))

	// Check Languages is a copy
	config2 := config.CopyForUpdate()
	require.True(t, config.IsEquivalent(config2))
	config2.Languages[0] = "python"
	require.False(t, config.IsEquivalent(config2))

	// Check InitialLanguages is a copy
	config2 = config.CopyForUpdate()
	require.True(t, config.IsEquivalent(config2))
	config2.InitialLanguages[0] = "python"
	require.False(t, config.IsEquivalent(config2))

	// Check QuerySuiteType is a deep copy
	config2 = config.CopyForUpdate()
	require.True(t, config.IsEquivalent(config2))
	config2.QuerySuiteType["root"] = ts.QuerySuite_DEFAULT
	require.False(t, config.IsEquivalent(config2))
}

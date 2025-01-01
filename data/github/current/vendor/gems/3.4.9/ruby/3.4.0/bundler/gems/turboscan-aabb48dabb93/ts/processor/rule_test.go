package processor

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysis"
	"github.com/github/turboscan/ts/mysql/configuration"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/github/turboscan/ts/mysql/rule"
	"github.com/github/turboscan/ts/mysql/timeline"
	"github.com/github/turboscan/ts/mysql/tool"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"

	"github.com/github/turboscan/ts/limits"

	"github.com/github/turboscan/ts/sarif/store"
	v2_1_0 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"
	"github.com/jinzhu/gorm"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/sarif/samples"
	"github.com/stretchr/testify/require"
)

func setUp(t *testing.T) (context.Context, *gorm.DB, *Processor) {
	t.Helper()
	db := dbtest.RequireConnection(t)
	ctx, cancel := context.WithCancel(context.Background())

	t.Cleanup(cancel)

	ruleS := rule.NewService(db)
	toolS := tool.NewService(db, limits.TestLimitSelector())
	ls := limits.NewLimitSelector(nil, false)
	sarifStore := store.NewSarifStore(config.STORAGE_MEMORY, &config.Config{MaxSarifSize: 0})
	err := sarifStore.Open(ctx)
	require.NoError(t, err)
	queue := &aqueduct.MockAqueductQueue{}
	client := &aqueduct.Client{
		Queue: queue,
	}

	p := &Processor{
		toolS:           toolS,
		configurationS:  configuration.NewService(db),
		rs:              ruleS,
		as:              alert.TestService(db),
		timelineS:       timeline.NewService(db),
		repos:           repository.NewService(db),
		analysisCreator: analysis.NewService(db),
		ls:              ls,
		ss:              sarifStore,
		archivalStore:   sarifStore,
		jobs:            client,
	}

	return ctx, db, p
}

func processResultsForRun(ctx context.Context, run *v2_1_0.Run, p *Processor) error {
	info := &ts.Delivery{
		RepositoryID:       testRepoID,
		SourceRepositoryID: testRepoID,
		Ref:                []byte("refs/heads/main"),
	}
	_, err := p.processResultsForRun(ctx, info, run)
	return err
}

func TestFindOrCreateRules(t *testing.T) {
	ctx, db, p := setUp(t)

	sarif := samples.RequireSARIF(t, "../sarif/testdata/rules.sarif")

	require.NoError(t, processResultsForRun(ctx, sarif.Runs[0], p))

	dbtest.RequireCount(t, 2, db.Model(&ts.Rule{}))
}

func TestFindOrCreateBadRules(t *testing.T) {
	ctx, _, p := setUp(t)

	sarif := samples.RequireSARIF(t, "../sarif/testdata/invalid_rule.sarif")
	err := processResultsForRun(ctx, sarif.Runs[0], p)
	require.Error(t, err)
}

func TestFindOrCreateRulesLoadTwice(t *testing.T) {
	ctx, db, p := setUp(t)

	sarif := samples.RequireSARIF(t, "../sarif/testdata/rules.sarif")
	require.NoError(t, processResultsForRun(ctx, sarif.Runs[0], p))
	require.NoError(t, processResultsForRun(ctx, sarif.Runs[0], p))

	dbtest.RequireCount(t, 2, db.Model(&ts.Rule{}))
}

func TestBySarifID(t *testing.T) {
	ctx, db, p := setUp(t)

	sarif := samples.RequireSARIF(t, "../sarif/testdata/rules.sarif")
	require.NoError(t, processResultsForRun(ctx, sarif.Runs[0], p))

	var actual ts.Rule
	require.NoError(t, db.Model(&ts.Rule{}).Where("sarif_identifier = ?", "js/unused-local-variable").First(&actual).Error)
	require.NotNil(t, actual)

	require.Equal(t, "js/unused-local-variable", actual.SarifIdentifier)
	// In this example the name and identifier are the same, but this is
	// not always the case.
	require.Equal(t, "js/unused-local-variable", actual.Name)
}

func TestSarifConversion(t *testing.T) {
	ctx, db, p := setUp(t)

	sarif := samples.RequireSARIF(t, "../sarif/testdata/rules.sarif")
	require.NoError(t, processResultsForRun(ctx, sarif.Runs[0], p))
	sarifRule := sarif.Runs[0].Tool.Driver.Rules[0]

	var actual ts.Rule
	err := db.Preload("Tags").
		First(&actual, "sarif_identifier = ?", "js/unused-local-variable").Error
	require.NoError(t, err)

	require.Equal(t, sarifRule.Id, actual.SarifIdentifier)
	require.Equal(t, sarifRule.Name, actual.Name)
	require.Equal(t, sarifRule.ShortDescription.Text, actual.ShortDescription)
	require.Equal(t, sarifRule.FullDescription.Text, actual.FullDescription)
	require.Equal(t, ts.SeverityLevelWarning, actual.SeverityLevel)
	require.Equal(t, sarifRule.Properties.Precision, actual.PrecisionLevel.String())
	require.Equal(t, sarifRule.Help.Markdown, actual.Help)
	require.Equal(t, sarifRule.HelpUri, actual.HelpURI)
	require.Equal(t, sarifRule.Properties.Tags[0], actual.Tags[0].Tag)
}

func TestMetricRules(t *testing.T) {
	ctx, db, p := setUp(t)

	metrics := samples.RequireSARIF(t, "../sarif/testdata/metrics.sarif")
	require.NoError(t, processResultsForRun(ctx, metrics.Runs[0], p))
	var sarifRule *v2_1_0.ReportingDescriptor
	for _, ext := range metrics.Runs[0].Tool.Extensions {
		if ext.Name == "codeql-cpp" && len(ext.Rules) > 0 {
			sarifRule = ext.Rules[0]
			break
		}
	}
	require.NotNil(t, sarifRule)

	var actual ts.Rule
	err := db.Preload("Tags").
		First(&actual, "sarif_identifier = ?", "cpp/summary/lines-of-code").Error
	require.NoError(t, err)

	require.Equal(t, sarifRule.Id, actual.SarifIdentifier)
	require.Equal(t, sarifRule.Name, actual.Name)
	require.Equal(t, sarifRule.ShortDescription.Text, actual.ShortDescription)
	require.Equal(t, sarifRule.FullDescription.Text, actual.FullDescription)

	storedTagNames := make([]string, len(actual.Tags))
	for i, tag := range actual.Tags {
		storedTagNames[i] = tag.Tag
	}

	require.ElementsMatch(t, sarifRule.Properties.Tags, storedTagNames)
}

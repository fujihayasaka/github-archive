package suggested_fixes

import (
	"context"
	"strconv"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mocks"
	asdb "github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/sarif/store"
	sf "github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
)

func setupService(t *testing.T) (
	*gorm.DB,
	context.Context,
	*Service,
	*spokes.MockSpokes,
	*aqueduct.AqueductMock,
	*mocks.MockSuggestedFixesAPI,
	*MockAutofixGeneratePublisher,
) {
	t.Helper()
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	store := store.TestMemoryStore()
	s := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	archiveService := archiver.NewService(db, store)
	mockAqueduct := &aqueduct.AqueductMock{}
	mockSpokes := &spokes.MockSpokes{}
	mockAutofixGeneratePublisher := &MockAutofixGeneratePublisher{}
	sfServ := sf.New(s, as, archiveService, ls, mockSpokes, sf.NewMockValidFixGenerator())
	sfServ.AutofixGeneratePublisher = mockAutofixGeneratePublisher
	mockCtrl := gomock.NewController(t)
	mockSuggestedFixesAPI := mocks.NewMockSuggestedFixesAPI(mockCtrl)
	sfServ.GitHubTwirpApiClient = mockSuggestedFixesAPI
	twirpSf := New(sfServ, store, mockAqueduct, nil)

	return db, ctx, twirpSf, mockSpokes, mockAqueduct, mockSuggestedFixesAPI, mockAutofixGeneratePublisher
}

func setupAlert(t *testing.T, db *gorm.DB, number uint32, filePath string, analysis *ts.Analysis, sarifId string, repoId ts.RepositoryEID) *ts.SuggestedFixAlert {
	t.Helper()
	sfas := setupAlerts(t, db, []uint32{number}, filePath, analysis, sarifId, repoId)
	return sfas[0]
}

func setupAlerts(t *testing.T, db *gorm.DB, numbers []uint32, filePath string, analysis *ts.Analysis, sarifId string, repoId ts.RepositoryEID) []*ts.SuggestedFixAlert {
	t.Helper()

	sfas := []*ts.SuggestedFixAlert{}

	if analysis == nil {
		tool := &ts.Tool{CanonicalName: "CodeQL"}
		require.NoError(t, db.FirstOrCreate(tool, tool).Error)
		tv := &ts.ToolVersion{Name: ts.ToolName("CodeQL"), ToolID: tool.ID, SemanticVersion: "2.0.1"}
		dbtest.RequireCreate(t, db, tv)
		analysis = &ts.Analysis{
			CommitOid:          "xxx",
			Ref:                []byte("refs/heads/ref1"),
			RepositoryID:       repoId,
			SourceRepositoryID: repoId,
			MostRecent:         true,
			AnalysisComplete:   true,
			Tool:               tool,
			ToolVersion:        tv,
		}
		require.NoError(t, db.Create(analysis).Error)
	}

	rule := &ts.Rule{
		SarifIdentifier: sarifId,
		Tool:            analysis.Tool,
	}
	dbtest.RequireCreate(t, db, rule)

	for _, number := range numbers {
		filePathWithNumber := filePath + strconv.Itoa(int(number))
		la := &ts.LogicalAlert{
			Number:                number,
			RepositoryID:          repoId,
			StableAlertIdentifier: []byte(filePathWithNumber),
			SarifIdentifier:       sarifId,
			RuleID:                rule.ID,
		}
		dbtest.RequireCreate(t, db, la)
		actual := &ts.LogicalAlert{}
		require.NoError(t, db.Where("number = ?", la.Number).First(actual).Error)
		require.Equal(t, la.Number, actual.Number)

		now := sqltime.Now()
		pa := &ts.PhysicalAlert{
			RepositoryID:          repoId,
			FilePath:              filePath,
			AnalysisID:            analysis.ID,
			LogicalAlertID:        la.ID,
			StableAlertIdentifier: []byte(filePathWithNumber),
			LastStateChangeAt:     now,
		}
		require.NoError(t, db.Create(pa).Error)
		actual_pa := &ts.PhysicalAlert{}
		require.NoError(t, db.Where("id = ?", pa.ID).First(actual_pa).Error)
		require.Equal(t, pa.AnalysisID, actual_pa.AnalysisID)

		pa.LogicalAlert = la
		pa.Analysis = analysis

		sf := &ts.SuggestedFix{
			RepositoryID: repoId,
			Description:  "test",
			AiVersion:    "test",
			AiModel:      "test",
		}
		sfa := &ts.SuggestedFixAlert{
			RepositoryID:        repoId,
			LogicalAlertNumber:  la.Number,
			RuleSarifIdentifier: "rule",
			RefBytes:            analysis.Ref,
			RequestedAt:         sqltime.Now(),
		}

		sfa.SetState(ts.SuggestedFixAlertStateValid, nil)
		files := []*ts.SuggestedFixFile{
			{
				RepositoryID: repoId,
				FilePath:     filePath,
				FileChecksum: ts.BuildFileChecksum([]byte("beef")),
				DiffContent:  []byte("test"),
			},
		}

		sf.Files = files
		sfa.SuggestedFix = sf
		sfa.PhysicalAlert = pa

		sfas = append(sfas, sfa)
	}

	return sfas
}

type MockAutofixGeneratePublisher struct {
	events []*tshydro.AutofixGenerateEvent
}

func (p *MockAutofixGeneratePublisher) AutofixGenerateEventBatch(_ context.Context, events []*tshydro.AutofixGenerateEvent) error {
	p.events = events

	return nil
}

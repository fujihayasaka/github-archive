package suggestedfixes

import (
	"context"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cocofix"
)

type MockFixGenerator struct {
	State                  ts.SuggestedFixAlertState
	GenerateFixCallCounter int
}

func (m *MockFixGenerator) Reset() {
	m.State = ts.SuggestedFixAlertStatePending
	m.GenerateFixCallCounter = 0
}

func (m *MockFixGenerator) GenerateFix(
	ctx context.Context,
	tool ts.ToolName,
	tv string,
	sfa *ts.SuggestedFixAlert,
	p bool,
	downloadFunc ts.DownloadFilesFunc,
	userID uint64,
	workload ts.ThrottlerWorkload) (ts.GenerateFixResult, error) {

	m.GenerateFixCallCounter += 1
	pa := sfa.PhysicalAlert
	b, _ := downloadFunc(ctx, pa.LogicalAlert.FilePath)

	sf := &ts.SuggestedFix{
		RepositoryID: pa.RepositoryID,
		Files: []*ts.SuggestedFixFile{
			{
				RepositoryID: pa.RepositoryID,
				FilePath:     pa.LogicalAlert.FilePath,
				FilePathHash: ts.BuildFilePathHash(pa.LogicalAlert.FilePath),
				FileChecksum: ts.BuildFileChecksum(b),
				DiffContent:  []byte(`diff --git a/foo/bar.js b/foo/bar.js`),
			},
		},
	}

	return ts.GenerateFixResult{
		SuggestedFixAlertState: m.State,
		SuggestedFix:           sf,
	}, nil
}

func (m *MockFixGenerator) GenerateDependabotFix(
	ctx context.Context,
	sarif string,
	filePaths []string,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	proximaEnv bool,
) (ts.GenerateFixResult, error) {

	sf := &ts.SuggestedFix{
		RepositoryID: repoID,
		Description:  "some description",
	}

	var files []*ts.SuggestedFixFile

	if len(filePaths) == 0 {
		files = append(files, &ts.SuggestedFixFile{
			RepositoryID: repoID,
			FilePath:     "src/index.js",
			FilePathHash: ts.BuildFilePathHash("src/index.js"),
			FileChecksum: ts.BuildFileChecksum([]byte("some content")),
			DiffContent:  []byte("index 1234567..abcdefg 100644"),
		})
	}

	for _, fp := range filePaths {
		b, _ := downloadFunc(ctx, fp)
		files = append(files, &ts.SuggestedFixFile{
			RepositoryID: repoID,
			FilePath:     fp,
			FilePathHash: ts.BuildFilePathHash(fp),
			FileChecksum: ts.BuildFileChecksum(b),
			DiffContent:  []byte("index 1234567..abcdefg 100644"),
		})
	}
	sf.Files = files

	return ts.GenerateFixResult{
		SuggestedFixAlertState: m.State,
		SuggestedFix:           sf,
	}, nil
}

func (m *MockFixGenerator) GetInputSarif() string {
	return ""
}

func NewMockValidFixGenerator() *MockFixGenerator {
	return &MockFixGenerator{State: ts.SuggestedFixAlertStateValid}
}

type EmptyFixGenerator struct {
	State                  ts.SuggestedFixAlertState
	GenerateFixCallCounter int
}

func (m *EmptyFixGenerator) Reset() {
	m.State = ts.SuggestedFixAlertStatePending
	m.GenerateFixCallCounter = 0
}

func (m *EmptyFixGenerator) GenerateFix(ctx context.Context,
	tool ts.ToolName,
	tv string,
	sfa *ts.SuggestedFixAlert,
	p bool,
	downloadFunc ts.DownloadFilesFunc,
	userID uint64,
	workload ts.ThrottlerWorkload) (ts.GenerateFixResult, error) {

	m.GenerateFixCallCounter += 1

	return ts.GenerateFixResult{
		SuggestedFixAlertState: m.State,
	}, nil
}

func (m *EmptyFixGenerator) GenerateDependabotFix(
	ctx context.Context,
	sarif string,
	filePaths []string,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	proximaEnv bool,
) (ts.GenerateFixResult, error) {

	m.GenerateFixCallCounter += 1

	return ts.GenerateFixResult{
		SuggestedFixAlertState: m.State,
	}, nil
}

func (m *EmptyFixGenerator) GetInputSarif() string {
	return ""
}

func NewMockInvalidFixGenerator() *EmptyFixGenerator {
	return &EmptyFixGenerator{State: ts.SuggestedFixAlertStateInvalid}
}

func NewMockErrorFixGenerator() *EmptyFixGenerator {
	return &EmptyFixGenerator{State: ts.SuggestedFixAlertStateError}
}

type ErrorFixGenerator struct {
	Error                  error
	GenerateFixCallCounter int
}

func (m *ErrorFixGenerator) GenerateFix(ctx context.Context,
	tool ts.ToolName,
	tv string,
	sfa *ts.SuggestedFixAlert,
	p bool,
	downloadFunc ts.DownloadFilesFunc,
	userID uint64,
	workload ts.ThrottlerWorkload) (ts.GenerateFixResult, error) {

	m.GenerateFixCallCounter += 1

	return ts.GenerateFixResult{}, m.Error
}

func (m *ErrorFixGenerator) GenerateDependabotFix(
	ctx context.Context,
	sarif string,
	filePaths []string,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	proximaEnv bool,
) (ts.GenerateFixResult, error) {

	return ts.GenerateFixResult{}, nil
}

func NewMockNonRetriableErrorFixGenerator() *ErrorFixGenerator {
	e := &cocofix.NonRetriableError{}
	return &ErrorFixGenerator{Error: e}
}

func NewMockTransientErrorFixGenerator() *ErrorFixGenerator {
	e := &cocofix.TransientError{}
	return &ErrorFixGenerator{Error: e}
}

type MockReporter struct {
}

func (mr MockReporter) Report(ctx context.Context, exception error, payload map[string]string) error {
	return nil
}

func (mr MockReporter) ReportSensitive(ctx context.Context, exception error, payload, sensitivePayload map[string]string) error {
	return nil
}

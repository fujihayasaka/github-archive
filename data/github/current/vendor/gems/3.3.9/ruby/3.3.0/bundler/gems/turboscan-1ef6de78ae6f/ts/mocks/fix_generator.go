package mocks

import (
	context "context"

	"github.com/pkg/errors"

	ts "github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/cocofix"
)

type TransientErrorGenerator struct{}

func (g *TransientErrorGenerator) GenerateFix(ctx context.Context, tool ts.ToolName, tv string, sfa *ts.SuggestedFixAlert, p bool, downloadFunc ts.DownloadFilesFunc, userID uint64, workload ts.ThrottlerWorkload) (ts.GenerateFixResult, error) {
	return ts.GenerateFixResult{}, &cocofix.TransientError{
		Err: errors.New("Transient error"),
	}
}

func (g *TransientErrorGenerator) GenerateDependabotFix(
	ctx context.Context,
	sarif string,
	filePaths []string,
	downloadFunc ts.DownloadFilesFunc,
	repoID ts.RepositoryEID,
	proximaEnv bool,
) (ts.GenerateFixResult, error) {

	return ts.GenerateFixResult{}, &cocofix.TransientError{
		Err: errors.New("Transient error"),
	}
}

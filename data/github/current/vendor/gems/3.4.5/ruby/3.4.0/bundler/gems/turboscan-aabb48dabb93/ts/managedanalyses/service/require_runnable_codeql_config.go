package managedanalyses

import (
	"context"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/flipper"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
)

var (
	ErrRequiredServicesNotEnabled = errors.New("Required services are not enabled")
)

// RequireRunnableCodeqlConfig reads the codeql config from the db and performs several sanity checks
// If the required services are disabled it will update the config disabling autocodeql
func (ma *ManagedAnalyses) RequireRunnableCodeqlConfig(ctx context.Context, repoID ts.RepositoryEID) (*ts.CodeqlConfig, *ts.ProximaTenant, ts.CodeqlPacks, error) {
	repo, err := ma.DataService.GetCodeqlRepo(ctx, repoID)
	if err != nil {
		return nil, nil, ts.CodeqlPacks(""), errors.Wrap(err, "failed to get codeql repo")
	}
	if repo.CurrentConfig == nil {
		return nil, nil, ts.CodeqlPacks(""), ts.ErrNotOnboarded
	}
	config := repo.CurrentConfig

	requiredServicesEnabled, tenant, codeqlPacks, err := ma.GitHubTwirpApiClient.AreRequiredServicesEnabled(ctx, config.RepositoryID)
	if err != nil {
		return nil, nil, ts.CodeqlPacks(""), errors.Wrap(err, "failed to check if required services are enabled")
	}

	if !requiredServicesEnabled {
		if !flipper.SkipOffboardingOnMissingServices(ctx, flipper.UnknownOrg, repoID) {
			appctx.Logger(ctx).Info("required services not enabled - offboarding repo", repoID.AsKVP())
			err = ma.OffboardRepo(ctx, repoID)
			// If the repo is already offboarded, we don't want to return an error
			if err != nil && !errors.Is(err, ts.ErrNoChangeRequired) {
				return nil, nil, ts.CodeqlPacks(""), errors.Wrap(err, "failed to offboard repo")
			}
		}
		return nil, nil, ts.CodeqlPacks(""), ErrRequiredServicesNotEnabled
	}

	return config, tenant, codeqlPacks, nil
}

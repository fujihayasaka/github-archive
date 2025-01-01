// Package repocheck runs a policy evaluation on a repository.
package repocheck

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/evaluator"
	"github.com/github/osslicensecompliance/internal/models"
)

// RepositoryCheckRequest provides the ability to check a repository against a policy.
// It holds the state necessary to run the check.
type RepositoryCheckRequest struct {
	Subsystems     *application.Subsystems
	EnterpriseID   uint64
	OrganizationID uint64
	RepositoryID   uint64
	Context        string
	CommitSHA      string
	BaseSHA        string
	Logger         log.Logger
}

// CheckRepository runs through all of the steps to evaluate a repository
// against applicable license policy.
func CheckRepository(ctx context.Context, rc RepositoryCheckRequest) (evaluator.RepositoryResults, error) {
	logger := rc.Logger.Named("repocheck").WithFields(
		kvp.Uint64("enterprise_id", rc.EnterpriseID),
		kvp.Uint64("organization_id", rc.OrganizationID),
		kvp.Uint64("repository_id", rc.RepositoryID),
		kvp.String("context", rc.Context),
		kvp.String("commitsha", rc.CommitSHA),
		kvp.String("basesha", rc.BaseSHA))
	logger.Debug("Checking repository")

	// Load the policy
	policy, err := rc.Subsystems.Storage.GetCompletePolicy(ctx, rc.EnterpriseID, rc.OrganizationID, rc.RepositoryID)
	if err != nil {
		return evaluator.RepositoryResults{}, fmt.Errorf("check repository failed to load policy: %w", err)
	}

	logger.Debug("Loaded policy")
	if policy.EnterprisePolicy != nil {
		logger.Debug(fmt.Sprintf("Enterprise policy: %d", policy.EnterprisePolicy.ID))
	}

	if policy.OrganizationPolicy != nil {
		logger.Debug(fmt.Sprintf("Organization policy: %d", policy.OrganizationPolicy.ID))
	}

	// Get the dependencies for the repository
	var deps map[string]models.Package

	// If BaseSHA is provided, use the new DRA diff dependencies
	deps, err = rc.Subsystems.DependencyGetter.GetDiffDependenciesForRepo(ctx, rc.RepositoryID, rc.CommitSHA, rc.BaseSHA)
	if err != nil {
		return evaluator.RepositoryResults{}, err
	}

	logger.Debug(fmt.Sprintf("Loaded %d dependencies", len(deps)))

	// Evaluate the policy against the dependencies
	results := evaluator.PolicyResultsForRepository(deps, policy, rc.Context, logger)
	logger.Debug(fmt.Sprintf("Policy evaluation results: %+v", results))
	return results, nil
}

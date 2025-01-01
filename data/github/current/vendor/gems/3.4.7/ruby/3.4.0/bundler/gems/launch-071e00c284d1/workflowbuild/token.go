package workflowbuild

import (
	"context"
	"encoding/json"

	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/clients/hydro/metadata"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

// TokenFactory provides methods to generate tokens to be passed to workflow builds
type TokenFactory interface {
	// NewToken returns a valid new token with the given permissions
	NewToken(ctx context.Context, repositoryID types.GlobalID, perms *tokens.InstallationPermissions, extendedPerms *tokens.ExtendedPermissions) (*tokens.AccessToken, error)

	// RefreshToken returns the current token with expended expiry time
	RefreshToken(ctx context.Context, token *tokens.AccessToken) (*tokens.AccessToken, error)

	// RevokeToken revokes the given token
	RevokeToken(ctx context.Context, repositoryID types.GlobalID, token *tokens.AccessToken) error

	// CalculateRunPermissions calculates the permission settings for a run
	CalculateRunPermissions(ctx context.Context, obs *observability.Observability, event string, ghe flowevents.GitHubEvent, defaultWorkflowPermissions types.DefaultWorkflowPermissions, forkPRPolicy types.ForkPRWorkflowsPolicy, actor *metadata.WorkflowMetadataActor) (*tokens.PermissionSettings, error)

	// CalculateJobPermissions calculates the permissions for a job
	CalculateJobPermissions(
		ctx context.Context,
		errReporter errorReporter,
		settings *tokens.PermissionSettings,
		requestedPerms map[string]string,
		workflowRunID int64,
		requestedWorkflowRunPerms map[string]string,
	) (*tokens.InstallationPermissions, *tokens.ExtendedPermissions, error)
}

type tokenFactory struct {
	tokenService          tokens.Service
	repoOrOwnersFFChecker func(ctx context.Context, featureFlag string, repositoryID types.GlobalID) bool
	env                   launchconfig.AppEnv
}

func NewTokenFactory(
	tokenService tokens.Service,
	repoOrOwnersFFChecker func(ctx context.Context, featureFlag string, repositoryID types.GlobalID) bool,
	env launchconfig.AppEnv,
) TokenFactory {
	return tokenFactory{
		tokenService:          tokenService,
		repoOrOwnersFFChecker: repoOrOwnersFFChecker,
		env:                   env,
	}
}

// CalculateRunPermissions calculates the permissions settings for a run
func (f tokenFactory) CalculateRunPermissions(ctx context.Context, obs *observability.Observability, event string, ghe flowevents.GitHubEvent, defaultWorkflowPermissions types.DefaultWorkflowPermissions, forkPRPolicy types.ForkPRWorkflowsPolicy, actor *metadata.WorkflowMetadataActor) (*tokens.PermissionSettings, error) {
	result := &tokens.PermissionSettings{}

	maxPerms := getMaxPermissions(ctx, obs, event, ghe, forkPRPolicy, actor)

	result.InstallationPermissions = *tokens.NewInstallationPermissions(maxPerms)

	// Determine if the default permissions for the GITHUB_TOKEN can inherit from maxPerms or if they need to be restricted
	// Users may opt to override these in their YAML
	if defaultWorkflowPermissions == types.LimitedReadWorkflowPermissions {
		// Admin policy, limit the default GITHUB_TOKEN to contents:read, packages:read
		result.DefaultPermissions = tokens.LimitedReadPermissions
	} else if clampDependabotDefaultPermissions(ctx, obs, event, actor) {
		// Needed to make sure that the default permissions are not increased as well, since the maxPerms for a Dependabot workflow have increased
		// See https://github.blog/changelog/2021-02-19-github-actions-workflows-triggered-by-dependabot-prs-will-run-with-read-only-permissions/
		result.DefaultPermissions = tokens.ReadPermissions
	} else {
		result.DefaultPermissions = maxPerms
	}

	// PR events need "sarifs" write access for CodeQL
	if event == flowevents.PullRequest || event == flowevents.PullRequestTarget {
		pr, err := flowevents.GetPullRequestNumber(ghe)
		if err != nil {
			return nil, err
		}

		if pr != nil {
			result.ExtendedPermissions = &tokens.ExtendedPermissions{
				PerPullRequestPermissions: &tokens.PerPullRequestPermissions{
					Number: *pr,
					Permissions: tokens.PullRequestInstallationPermissions{
						Sarifs: "write",
					},
				},
			}
		}
	}

	return result, nil
}

// getMaxPermissions checks to see if any conditions exist that should result in the permissions being escalated to write permissions, if none are present, it returns read permissions.
func getMaxPermissions(ctx context.Context, obs *observability.Observability, event string, ghe flowevents.GitHubEvent, forkPRPolicy types.ForkPRWorkflowsPolicy, actor *metadata.WorkflowMetadataActor) tokens.TokenPermissionSet {
	// Start at read until we find a condition that warrants escalating to write. This is done to avoid
	// accidentally granting write permissions for some edge cases.
	//
	// For context on this see https://github.com/github/c2c-actions-experience/issues/4439
	maxPerms := tokens.ReadPermissions

	isRestrictedForkPREvent := flowevents.IsRestrictedForkPREvent(event, ghe)
	writeForkPolicy := forkPRPolicy.ShouldSendWriteToken()

	// Fork PRs can be an attack vector, so we need to limit them to read permissions, unless a policy is set to send write tokens
	// See https://securitylab.github.com/research/github-actions-preventing-pwn-requests/
	notForkOrPolicyEnabled := !isRestrictedForkPREvent || writeForkPolicy

	if notForkOrPolicyEnabled {
		if flowevents.IsDependabotActor(actor) {
			maxPerms = getDependabotActorMaxPermissions(ctx, obs, event)
		} else {
			maxPerms = tokens.WritePermissions
		}
	}

	return maxPerms
}

func getDependabotActorMaxPermissions(ctx context.Context, obs *observability.Observability, event string) tokens.TokenPermissionSet {
	restrictionLevel := flowevents.GetDependabotRestrictionLevel(ctx, obs, event)

	switch restrictionLevel {
	case flowevents.DependabotActorNotExpected:
		obs.Logger.Error(ctx, "Unexpected event type triggered by Dependabot. Using full dependabot restrictions")
		return tokens.ReadPermissions

	case flowevents.DependabotFullyRestricted:
		return tokens.ReadPermissions

	case flowevents.DependabotPartiallyRestricted:
		return tokens.WritePermissions

	case flowevents.DependabotUnrestricted:
		return tokens.WritePermissions

	default:
		obs.Logger.Error(ctx, "Restriction level not supported. Using full dependabot restrictions",
			kvp.String("gh.launch.dependabot_restrictions", string(restrictionLevel)))

		return tokens.ReadPermissions
	}
}

func clampDependabotDefaultPermissions(ctx context.Context, obs *observability.Observability, event string, actor *metadata.WorkflowMetadataActor) bool {
	// This only applies to Dependabot
	if !flowevents.IsDependabotActor(actor) {
		return false
	}

	restrictionLevel := flowevents.GetDependabotRestrictionLevel(ctx, obs, event)

	switch restrictionLevel {
	case flowevents.DependabotActorNotExpected:
		obs.Logger.Error(ctx, "Unexpected event type triggered by Dependabot. Using full dependabot restrictions")
		return true

	case flowevents.DependabotFullyRestricted:
		return true

	case flowevents.DependabotPartiallyRestricted:
		return true

	case flowevents.DependabotUnrestricted:
		return false

	default:
		obs.Logger.Error(ctx, "Restriction level not supported. Using full dependabot restrictions",
			kvp.String("gh.launch.dependabot_restrictions", string(restrictionLevel)))
		return true
	}
}

type errorReporter interface {
	Report(ctx context.Context, err error, fields ...kvp.Field)
}

func (f tokenFactory) CalculateJobPermissions(
	ctx context.Context,
	errReporter errorReporter,
	settings *tokens.PermissionSettings,
	requestedPerms map[string]string,
	workflowRunID int64,
	requestedWorkflowRunPerms map[string]string,
) (result *tokens.InstallationPermissions, extendedPermissions *tokens.ExtendedPermissions, err error) {
	// Validate args
	if settings == nil {
		return nil, nil, errors.Errorf("settings must not be nil")
	} else if settings.DefaultPermissions == "" {
		return nil, nil, errors.Errorf("settings.DefaultPermissions must not be empty")
	}

	if requestedPerms == nil {
		// Default permissions
		result = tokens.NewInstallationPermissions(settings.DefaultPermissions)
	} else {
		// Deserialize requested permissions
		result = &tokens.InstallationPermissions{}
		serialized, err := json.Marshal(requestedPerms)
		if err != nil {
			return nil, nil, err
		}
		err = json.Unmarshal(serialized, result)
		if err != nil {
			return nil, nil, err
		}

		// Ensure Metadata:read
		result.Metadata = tokens.ReadAccess
	}

	extendedPermissions = settings.ExtendedPermissions
	// Calculate extended permissions for a workflow run
	if len(requestedWorkflowRunPerms) > 0 {
		workflowRunPermissions := &tokens.WorkflowRunInstallationPermissions{}
		serialized, err := json.Marshal(requestedWorkflowRunPerms)
		if err != nil {
			return nil, nil, err
		}
		err = json.Unmarshal(serialized, workflowRunPermissions)
		if err != nil {
			return nil, nil, err
		}

		if workflowRunPermissions.Valid() {
			if extendedPermissions == nil {
				extendedPermissions = &tokens.ExtendedPermissions{}
			}
			extendedPermissions.PerWorkflowRunPermissions = &tokens.PerWorkflowRunPermissions{
				ID:          workflowRunID,
				Permissions: workflowRunPermissions,
			}
		} else {
			errReporter.Report(ctx,
				errors.New("invalid workflow run permissions"),
				kvp.Any("gh.launch.requested_workflow_run_permissions", requestedWorkflowRunPerms),
				kvp.Int64("gh.actions.workflow_run.id", workflowRunID))
		}
	}

	// Limit to max permissions
	err = result.MergeMinimum(&settings.InstallationPermissions)
	if err != nil {
		return nil, nil, err
	}

	return result, extendedPermissions, nil
}

func (f tokenFactory) NewToken(ctx context.Context, repositoryID types.GlobalID, perms *tokens.InstallationPermissions, extendedPerms *tokens.ExtendedPermissions) (*tokens.AccessToken, error) {
	return f.tokenService.SiteScopedTokenForRepository(ctx, repositoryID, 0, false, perms, extendedPerms)
}

func (f tokenFactory) RefreshToken(ctx context.Context, token *tokens.AccessToken) (*tokens.AccessToken, error) {
	refreshedToken, err := f.tokenService.RefreshToken(ctx, token)
	if err != nil {
		return nil, err
	}

	return refreshedToken, nil
}

func (f tokenFactory) RevokeToken(ctx context.Context, repositoryID types.GlobalID, token *tokens.AccessToken) error {
	return f.tokenService.RevokeToken(ctx, repositoryID, token)
}

type NullTokenFactory struct {
}

func (f NullTokenFactory) NewToken(_ context.Context, _ types.GlobalID, _ int64, _ *tokens.InstallationPermissions, _ *tokens.ExtendedPermissions) (*tokens.AccessToken, error) {
	return nil, nil
}

func (f NullTokenFactory) RefreshToken(_ context.Context, _ types.GlobalID, _ int64, _ *tokens.AccessToken) (*tokens.AccessToken, error) {
	return nil, nil
}

func (f NullTokenFactory) RevokeToken(_ context.Context, _ types.GlobalID, _ *tokens.AccessToken) error {
	return nil
}

func (f NullTokenFactory) CalculateRunPermissions(_ context.Context, _ string, _ flowevents.GitHubEvent, _ types.DefaultWorkflowPermissions, _ types.ForkPRWorkflowsPolicy, _ *metadata.WorkflowMetadataActor) (*tokens.PermissionSettings, error) {
	return nil, nil
}

func (f NullTokenFactory) CalculateJobPermissions(_ context.Context, _ *tokens.PermissionSettings, _ map[string]string) (*tokens.InstallationPermissions, error) {
	return nil, nil
}

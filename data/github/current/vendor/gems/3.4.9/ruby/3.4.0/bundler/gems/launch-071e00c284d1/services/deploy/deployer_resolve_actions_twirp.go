package deploy

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/authzd"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability/statter"

	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
	"github.com/github/launch/utils"

	authzpb "github.com/github/authzd/pkg/proto"

	"github.com/twitchtv/twirp"

	ghactions "github.com/github/launch/proto/monolith/core/v1"
	terrors "github.com/github/launch/types/errors"
)

type ActionRepository struct {
	ID   int64
	Name string
	Ref  string
	Path string
}

func (s *service) resolveActionsWithTwirp(ctx context.Context, actions []*pb.ActionReference, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo, workflowRunID int64, jobID string, workflowRepoID types.GlobalID, isHostedRunner bool) (*pb.ResolveActionsResponse, error) {
	repositoryID, err := globalIDToRepositoryID(workflowRepoID)
	if err != nil {
		return nil, errors.Wrap(err, "failed to get workflow_repository_id")
	}

	s.cfg.Log.Debug(ctx, "attempting to resolve actions with twirp",
		kvp.Int64("gh.launch.actions_count", int64(len(actions))),
		kvp.Int64("gh.launch.workflow_run.id", workflowRunID),
		kvp.String("gh.launch.job.id", jobID),
		kvp.Uint64("gh.launch.workflow_repository.id", repositoryID),
	)

	s.cfg.Stats.Counter(ctx, "resolve_actions_count", nil, int64(len(actions)))

	// Resolving actions for private workflow repositories
	if arePrivateActionsEnabled(actionsPolicyInfo) {
		s.cfg.Log.Debug(ctx, "resolving private action")

		return s.resolveActionsForPrivateWorkflowRepository(ctx, actions, actionsPolicyInfo, workflowRunID, jobID, int64(repositoryID), isHostedRunner)
	}

	// Resolving actions for internal workflow repositories
	if areInternalActionsEnabled(actionsPolicyInfo) {
		s.cfg.Log.Debug(ctx, "resolving internal action")
		return s.resolveActionsForInternalWorkflowRepository(ctx, actions, actionsPolicyInfo, workflowRunID, jobID, int64(repositoryID), isHostedRunner)
	}

	// Resolving actions for public workflow repositories
	s.cfg.Log.Debug(ctx, "resolving public action")
	return s.resolveActionsForPublicWorkflowRepository(ctx, actions, actionsPolicyInfo, workflowRunID, jobID, int64(repositoryID), isHostedRunner)
}

func (s *service) resolveActionsForPublicWorkflowRepository(ctx context.Context, actions []*pb.ActionReference, actionsPolicyInfo *ghtwirp.ActionsPolicyInfo, workflowRunID int64, jobID string, wfRepoID int64, isHostedRunner bool) (*pb.ResolveActionsResponse, error) {
	twirpResp, err := s.resolveActions(ctx, actions, workflowRunID, jobID, wfRepoID, isHostedRunner)
	if err != nil {
		return s.buildTwirpErrorResponse(ctx, actions, err)
	}

	// List of actions that we try to resolve with GH Connect (in case of GHES)
	// or Actions Proxima Integrations (in case of Proxima stamps)
	var actionsToResolveWithDotcom []*pb.ActionReference
	localOnlyActionsMap := s.prepareLocalOnlyActionsMap(actionsPolicyInfo)

	resolveActionsResponse := &pb.ResolveActionsResponse{}
	for i, resolvedActionTwirpResp := range twirpResp {
		// Check if the actions resolution failed with
		// an error raised from the twirp endpoint
		if resolvedActionTwirpResp.Error != nil {
			// Applicable to Proxima stamps.

			if s.shouldFallbackToDotcomToResolveAction(actions[i], resolvedActionTwirpResp.Error, localOnlyActionsMap) {
				actionsToResolveWithDotcom = append(actionsToResolveWithDotcom, actions[i])
				continue
			}

			errMsg := resolvedActionTwirpResp.Error.Err.Error()
			s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", actions[i].NameWithVersion()), kvp.Err(resolvedActionTwirpResp.Error.Err))
			resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, &pb.ResolvedActionError{
				Action:  actions[i],
				Message: errMsg,
			})
			continue
		}

		// Check if the workflow is trying to access a private or internal
		// action from a public repo. We should throw a not
		// found error in such cases.
		resolvedAction := resolvedActionTwirpResp.ResolvedAction
		if isPrivateOrInternal(resolvedAction.Visibility) {
			errMsg := fmt.Sprintf("Unable to resolve action `%s`, not found", resolvedAction.Name)
			s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", actions[i].NameWithVersion()))
			resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, &pb.ResolvedActionError{
				Action:  actions[i],
				Message: errMsg,
			})
			continue
		}

		s.cfg.Log.Log(ctx, "Successfully resolved action", kvp.String("gh.launch.action_name_version", resolvedAction.ResolvedName))

		// At this point, append the resolved public action to the response
		resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(resolvedAction, actions[i], nil))
	}

	if len(actionsToResolveWithDotcom) > 0 {
		resolvedActionsWithDotcom, err := s.resolveActionsFallingBackToDotcom(ctx, actionsToResolveWithDotcom, workflowRunID, jobID, wfRepoID)
		if err != nil {
			return nil, err
		}

		resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, resolvedActionsWithDotcom.Actions...)
		resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, resolvedActionsWithDotcom.Errors...)
	}

	return resolveActionsResponse, nil
}

func (s *service) resolveActionsForInternalWorkflowRepository(
	ctx context.Context,
	actions []*pb.ActionReference,
	actionsPolicyInfo *ghtwirp.ActionsPolicyInfo,
	workflowRunID int64,
	jobID string,
	wfRepoID int64,
	isHostedRunner bool,
) (*pb.ResolveActionsResponse, error) {
	twirpResp, err := s.resolveActions(ctx, actions, workflowRunID, jobID, wfRepoID, isHostedRunner)
	if err != nil {
		return s.buildTwirpErrorResponse(ctx, actions, err)
	}

	// List of actions that we try to resolve with GH Connect (in case of GHES)
	// or Actions Proxima Integrations (in case of Proxima stamps)
	var actionsToResolveWithDotcom []*pb.ActionReference
	localOnlyActionsMap := s.prepareLocalOnlyActionsMap(actionsPolicyInfo)

	resolveActionsResponse := &pb.ResolveActionsResponse{}
	internalActionNameToResolvedActionRespMap := make(map[string]*ghtwirp.ResolveActionsResponse)
	var redirectedActions []string
	var internalActionRepos []*ActionRepository
	for i, resolvedActionTwirpResp := range twirpResp {
		// Check if actions resolution failed with
		// an error raised from the twirp endpoint
		if resolvedActionTwirpResp.Error != nil {
			// Applicable to Proxima stamps.
			if s.shouldFallbackToDotcomToResolveAction(actions[i], resolvedActionTwirpResp.Error, localOnlyActionsMap) {
				actionsToResolveWithDotcom = append(actionsToResolveWithDotcom, actions[i])
				continue
			}

			errMsg := resolvedActionTwirpResp.Error.Err.Error()
			s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", actions[i].NameWithVersion()), kvp.Err(resolvedActionTwirpResp.Error.Err))
			resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, &pb.ResolvedActionError{
				Action:  actions[i],
				Message: errMsg,
			})
			continue
		}

		// Check if the workflow is trying to access a private action (repo or package).
		// Throw a not found error in such cases
		resolvedAction := resolvedActionTwirpResp.ResolvedAction
		if isPrivate(resolvedAction.Visibility) {
			s.cfg.Log.Debug(ctx, "resolved action, is private")
			errMsg := fmt.Sprintf("Unable to resolve action `%s`, not found", resolvedAction.Name)
			s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", actions[i].NameWithVersion()))
			resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, &pb.ResolvedActionError{
				Action:  actions[i],
				Message: errMsg,
			})
			continue
		}

		// Accummulate information about internal repository actions to perform authz validations & token generation
		// Only repositories require authz checks & tokens, since packages returned from twirp have already been authorized in the Packages services
		// and use presigned URLs to allow runners to download the package
		if isInternalRepository(resolvedAction) {
			// Add the action to the response if it is a self
			// referencing internal action
			if resolvedAction.Id == wfRepoID {
				resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(resolvedAction, actions[i], nil))
				continue
			}

			internalAction := &ActionRepository{
				ID:   resolvedAction.Id,
				Name: actions[i].Name,
				Ref:  actions[i].Version,
				Path: actions[i].Path,
			}

			internalActionRepos = append(internalActionRepos, internalAction)

			// Check if the action request got redirected
			if !strings.EqualFold(resolvedAction.Name, resolvedAction.ResolvedName) {
				redirectedActions = append(redirectedActions, resolvedAction.Name)
			}

			internalActionNameToResolvedActionRespMap[internalAction.buildActionNameWithVersion()] = resolvedActionTwirpResp
			continue
		}

		// At this point, the resolved action is either a public repository or a public / internal package

		// Check if the request got redirected
		if !strings.EqualFold(resolvedAction.Name, resolvedAction.ResolvedName) {
			redirectedActions = append(redirectedActions, resolvedAction.Name)
		}

		s.cfg.Log.Log(ctx, "Successfully resolved action", kvp.String("gh.launch.action_name_version", resolvedAction.ResolvedName))

		// Append the resolved action to the response
		resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(resolvedAction, actions[i], nil))
	}

	// We don't support redirects in GHEC
	if len(redirectedActions) > 0 {
		return s.buildRedirectedActionsErrorResponse(ctx, redirectedActions), nil
	}

	// If there are internal actions repos referenced consult authz
	// before minting scoped installation tokens
	if len(internalActionRepos) > 0 {
		var authzInputRepos []*authzd.RepositoryParam
		for _, internalActionRepo := range internalActionRepos {
			authzInputRepos = append(authzInputRepos, &authzd.RepositoryParam{
				ID:   uint64(internalActionRepo.ID),
				Name: internalActionRepo.Name,
			})
		}

		s.cfg.Log.Debug(ctx, "validating actions share policy with authz", kvp.Int("gh.launch.actions_count", len(authzInputRepos)))

		authzDecisionsResult, err := s.AuthzClient.BatchAuthorize(ctx, uint64(wfRepoID), authzInputRepos)
		if err != nil {
			return nil, errors.Wrap(err, "could not validate authz permissions")
		}

		var inaccessibleInternalActionRepos []string
		for i, decision := range authzDecisionsResult.Decisions {
			if decision.Result != authzpb.Result_ALLOW {
				inaccessibleInternalActionRepos = append(inaccessibleInternalActionRepos, internalActionRepos[i].Name)
			}
		}

		if len(inaccessibleInternalActionRepos) > 0 {
			return s.handleInaccessibleInternalActionRepos(ctx, inaccessibleInternalActionRepos)
		}

		// Skip scoped token generation if there are any errors encountered
		// till this point
		if len(resolveActionsResponse.Errors) > 0 {
			return resolveActionsResponse, nil
		}

		s.cfg.Log.Debug(ctx, "Get scoped owner-token map for internal actions repos")

		scopedTokenMap := make(map[string]*ownerToken)
		for _, resolvedActionResp := range internalActionNameToResolvedActionRespMap {
			repo, err := types.ParseNWO(resolvedActionResp.ResolvedAction.Name)
			if err != nil {
				return nil, errors.Wrap(err, "parsing action name")
			}

			repoOwner := strings.ToLower(repo.Owner)
			if ownerToken, found := scopedTokenMap[repoOwner]; found {
				ownerToken.repositories.add(repo.Name)
				continue
			}

			scopedTokenMap[repoOwner] = newOwnerToken(nil, nil, repo.Name)
		}

		// Iterate over the actions owners and add tokens to the existing owner/repositories map
		s.cfg.Log.Debug(ctx, "Fetching scoped tokens for action repos under each owner",
			kvp.Int("gh.launch.actions_owners_count", len(scopedTokenMap)),
		)

		for owner, ownerToken := range scopedTokenMap {
			token, err := s.fetchTokenForRepos(ctx, owner, ownerToken)
			if err != nil {
				return nil, errors.Wrapf(err, "for action owner %q", owner)
			}

			ownerToken.token = token
		}

		for actionNameWithVersion, resolvedActionResp := range internalActionNameToResolvedActionRespMap {
			actionNwo, path, ref, err := parseNameWithVersion(actionNameWithVersion)
			if err != nil {
				return nil, err
			}

			repo, err := types.ParseNWO(actionNwo)
			if err != nil {
				return nil, errors.Wrap(err, "parsing action name")
			}

			resolvedAction := resolvedActionResp.ResolvedAction
			scopedAccessToken := scopedTokenMap[strings.ToLower(repo.Owner)]

			s.cfg.Log.Log(ctx, "Successfully resolved action", kvp.String("gh.launch.action_name_version", resolvedAction.ResolvedName))
			s.cfg.Stats.Counter(ctx, "resolve_internal_actions_count", nil, 1)
			resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(
				resolvedAction,
				&pb.ActionReference{
					Name:    actionNwo,
					Version: ref,
					Path:    path,
				},
				scopedAccessToken.token,
			))
		}

		if !s.IsEnterprise {
			err = s.delayResolveActionsResponseForTheAmountOfReplicationLag(ctx, scopedTokenMap)
			if err != nil {
				return nil, err
			}
		}
	}

	if len(actionsToResolveWithDotcom) > 0 {
		resolvedActionsWithDotcom, err := s.resolveActionsFallingBackToDotcom(ctx, actionsToResolveWithDotcom, workflowRunID, jobID, wfRepoID)
		if err != nil {
			return nil, err
		}

		resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, resolvedActionsWithDotcom.Actions...)
		resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, resolvedActionsWithDotcom.Errors...)
	}

	return resolveActionsResponse, nil
}

//gocyclo:ignore
func (s *service) resolveActionsForPrivateWorkflowRepository(
	ctx context.Context,
	actions []*pb.ActionReference,
	actionsPolicyInfo *ghtwirp.ActionsPolicyInfo,
	workflowRunID int64,
	jobID string,
	wfRepoID int64,
	isHostedRunner bool,
) (*pb.ResolveActionsResponse, error) {
	twirpResp, err := s.resolveActions(ctx, actions, workflowRunID, jobID, wfRepoID, isHostedRunner)
	if err != nil {
		return s.buildTwirpErrorResponse(ctx, actions, err)
	}

	// List of actions that we try to resolve with GH Connect (in case of GHES)
	// or Actions Proxima Integrations (in case of Proxima stamps)
	var actionsToResolveWithDotcom []*pb.ActionReference
	localOnlyActionsMap := s.prepareLocalOnlyActionsMap(actionsPolicyInfo)

	resolveActionsResponse := &pb.ResolveActionsResponse{}
	internalOrPrivateActionNameToResolvedActionRespMap := make(map[string]*ghtwirp.ResolveActionsResponse)
	var internalOrPrivateActionRepos []*ActionRepository
	var redirectedPublicActions []string
	var redirectedInternalOrPrivateActions []string
	var internalActionsCount int64
	for i, resolvedActionTwirpResp := range twirpResp {
		// Check if the actions resolution failed with
		// an error raised from the twirp endpoint
		if resolvedActionTwirpResp.Error != nil {
			// Applicable to Proxima stamps.
			if s.shouldFallbackToDotcomToResolveAction(actions[i], resolvedActionTwirpResp.Error, localOnlyActionsMap) {
				actionsToResolveWithDotcom = append(actionsToResolveWithDotcom, actions[i])
				continue
			}

			errMsg := resolvedActionTwirpResp.Error.Err.Error()
			s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", actions[i].NameWithVersion()), kvp.Err(resolvedActionTwirpResp.Error.Err))
			resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, &pb.ResolvedActionError{
				Action:  actions[i],
				Message: errMsg,
			})
			continue
		}

		resolvedAction := resolvedActionTwirpResp.ResolvedAction

		// Accummulate information about private and internal actions to perform authz validations & token generation
		// Only repositories require authz checks & tokens, since packages returned from twirp have already been authorized in the Packages services
		// and use presigned URLs to allow runners to download the package
		if isPrivateOrInternalRepository(resolvedAction) {
			// Add the action to the response if it is a self
			// referencing private action
			if resolvedAction.Id == wfRepoID {
				resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(resolvedAction, actions[i], nil))
				continue
			}

			if isInternal(resolvedAction.Visibility) {
				internalActionsCount++
			}

			internalOrPrivateActionRepo := &ActionRepository{
				ID:   resolvedAction.Id,
				Name: actions[i].Name,
				Ref:  actions[i].Version,
				Path: actions[i].Path,
			}
			internalOrPrivateActionRepos = append(internalOrPrivateActionRepos, internalOrPrivateActionRepo)

			// Check if the action request got redirected
			if !strings.EqualFold(resolvedAction.Name, resolvedAction.ResolvedName) {
				redirectedInternalOrPrivateActions = append(redirectedInternalOrPrivateActions, resolvedAction.Name)
			}

			internalOrPrivateActionNameToResolvedActionRespMap[internalOrPrivateActionRepo.buildActionNameWithVersion()] = resolvedActionTwirpResp
			continue
		}

		// At this point, the resolved action is either a public repository or a public / internal / private package

		// Check if the action request got redirected
		if !strings.EqualFold(resolvedAction.Name, resolvedAction.ResolvedName) {
			if isPrivateOrInternal(resolvedAction.Visibility) {
				redirectedInternalOrPrivateActions = append(redirectedInternalOrPrivateActions, resolvedAction.Name)
			} else {
				redirectedPublicActions = append(redirectedPublicActions, resolvedAction.Name)
			}
		}

		s.cfg.Log.Log(ctx, "Successfully resolved action", kvp.String("gh.launch.action_name_version", resolvedAction.ResolvedName))

		// At this point, append the resolved public action to the response
		resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(resolvedAction, actions[i], nil))
	}

	// We don't support redirects for resolving actions in GHEC private workflow repositories
	isNonEnterpriseWorkflowRepo := !areInternalActionsEnabled(actionsPolicyInfo) && arePrivateActionsEnabled(actionsPolicyInfo)
	if !isNonEnterpriseWorkflowRepo && (len(redirectedPublicActions) > 0 || len(redirectedInternalOrPrivateActions) > 0) {
		var redirectedActions = append(redirectedPublicActions, redirectedInternalOrPrivateActions...)
		return s.buildRedirectedActionsErrorResponse(ctx, redirectedActions), nil
	}

	// We don't support redirects for private/internal actions.
	if len(redirectedInternalOrPrivateActions) > 0 {
		return s.buildRedirectedActionsErrorResponse(ctx, redirectedInternalOrPrivateActions), nil
	}

	// If there are internal or private actions referenced, we should authenticate
	// them with Authz before generating scoped installation tokens
	if len(internalOrPrivateActionRepos) > 0 {
		var authzInput []*authzd.RepositoryParam
		for _, internalOrPrivateActionRepo := range internalOrPrivateActionRepos {
			authzInput = append(authzInput, &authzd.RepositoryParam{
				ID:   uint64(internalOrPrivateActionRepo.ID),
				Name: internalOrPrivateActionRepo.Name,
			})
		}

		s.cfg.Log.Debug(ctx, "validating actions share policy with authz", kvp.Int("gh.launch.actions_count", len(authzInput)))

		authzDecisionsResult, err := s.AuthzClient.BatchAuthorize(ctx, uint64(wfRepoID), authzInput)
		if err != nil {
			return nil, errors.Wrap(err, "could not validate authz permissions")
		}

		var inaccessibleInternalActionRepos []string
		for i, decision := range authzDecisionsResult.Decisions {
			if decision.Result != authzpb.Result_ALLOW {
				actionRepo := internalOrPrivateActionRepos[i]
				actionNameWithVersion := actionRepo.buildActionNameWithVersion()
				resolvedActionResp, ok := internalOrPrivateActionNameToResolvedActionRespMap[actionNameWithVersion]
				if !ok {
					return nil, errors.Errorf("failed to dereference resolved action %s", actionNameWithVersion)
				}

				if isInternal(resolvedActionResp.ResolvedAction.Visibility) {
					inaccessibleInternalActionRepos = append(inaccessibleInternalActionRepos, resolvedActionResp.ResolvedAction.Name)
					continue
				}

				// Unauthorized private repos should be thrown a not found error
				errMsg := fmt.Sprintf("Unable to resolve action `%s`, repository not found", resolvedActionResp.ResolvedAction.Name)
				s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", actionRepo.Name))
				resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, &pb.ResolvedActionError{
					Action: &pb.ActionReference{
						Name:    actionRepo.Name,
						Version: actionRepo.Ref,
						Path:    actionRepo.Path,
					},
					Message: errMsg,
				})
			}
		}

		if len(inaccessibleInternalActionRepos) > 0 {
			return s.handleInaccessibleInternalActionRepos(ctx, inaccessibleInternalActionRepos)
		}

		// Skip scoped token generation if there are any errors encountered
		// till this point
		if len(resolveActionsResponse.Errors) > 0 {
			return resolveActionsResponse, nil
		}

		s.cfg.Log.Debug(ctx, "Get scoped owner-token map for internal and private actions")

		scopedTokenMap := make(map[string]*ownerToken)
		for _, resolvedActionResp := range internalOrPrivateActionNameToResolvedActionRespMap {
			repo, err := types.ParseNWO(resolvedActionResp.ResolvedAction.Name)
			if err != nil {
				return nil, errors.Wrap(err, "parsing action name")
			}

			repoOwner := strings.ToLower(repo.Owner)
			if ownerToken, found := scopedTokenMap[repoOwner]; found {
				ownerToken.repositories.add(repo.Name)
				continue
			}

			scopedTokenMap[repoOwner] = newOwnerToken(nil, nil, repo.Name)
		}

		// Iterate over the actions owners and add tokens to the existing owner/repositories map
		s.cfg.Log.Debug(ctx, "Fetching scoped tokens for action repos under each owner",
			kvp.Int("gh.launch.actions_owners_count", len(scopedTokenMap)),
		)

		for owner, ownerToken := range scopedTokenMap {
			token, err := s.fetchTokenForRepos(ctx, owner, ownerToken)
			if err != nil {
				return nil, errors.Wrapf(err, "for action owner %q", owner)
			}

			ownerToken.token = token
		}

		for actionNameWithVersion, resolvedActionResp := range internalOrPrivateActionNameToResolvedActionRespMap {
			actionNwo, path, ref, err := parseNameWithVersion(actionNameWithVersion)
			if err != nil {
				return nil, err
			}

			repo, err := types.ParseNWO(actionNwo)
			if err != nil {
				return nil, errors.Wrap(err, "parsing action name")
			}

			resolvedAction := resolvedActionResp.ResolvedAction
			scopedAccessToken := scopedTokenMap[strings.ToLower(repo.Owner)]

			s.cfg.Log.Log(ctx, "Successfully resolved action", kvp.String("gh.launch.action_name_version", resolvedAction.ResolvedName))
			resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, twirpResolvedActionToDeployerProto(
				resolvedAction,
				&pb.ActionReference{
					Name:    actionNwo,
					Version: ref,
					Path:    path,
				},
				scopedAccessToken.token,
			))
		}

		if !s.IsEnterprise {
			err = s.delayResolveActionsResponseForTheAmountOfReplicationLag(ctx, scopedTokenMap)
			if err != nil {
				return nil, err
			}
		}

		s.collectPrivateAndInternalActionsUsageStats(ctx, arePrivateActionsEnabled(actionsPolicyInfo), isNonEnterpriseWorkflowRepo, internalActionsCount, int64(len(internalOrPrivateActionNameToResolvedActionRespMap)))
	}

	if len(actionsToResolveWithDotcom) > 0 {
		resolvedActionsWithDotcom, err := s.resolveActionsFallingBackToDotcom(ctx, actionsToResolveWithDotcom, workflowRunID, jobID, wfRepoID)
		if err != nil {
			return nil, err
		}

		resolveActionsResponse.Actions = append(resolveActionsResponse.Actions, resolvedActionsWithDotcom.Actions...)
		resolveActionsResponse.Errors = append(resolveActionsResponse.Errors, resolvedActionsWithDotcom.Errors...)
	}

	return resolveActionsResponse, nil
}

func (s *service) resolveActions(ctx context.Context, actions []*pb.ActionReference, workflowRunID int64, jobID string, workflowRepoID int64, isHostedRunner bool) ([]*ghtwirp.ResolveActionsResponse, error) {
	var requestActions []*ghtwirp.Action
	for _, action := range actions {
		requestActions = append(requestActions, &ghtwirp.Action{
			Nwo:  action.Name,
			Ref:  action.Version,
			Path: action.Path,
		})
	}

	return s.cfg.GithubTwirpClient.ResolveActions(ctx, requestActions, workflowRunID, jobID, workflowRepoID, true, isHostedRunner)
}

func (s *service) resolveActionsFallingBackToDotcom(ctx context.Context, actions []*pb.ActionReference, workflowRunID int64, jobID string, wfRepoID int64) (*pb.ResolveActionsResponse, error) {
	resolvedActionsResponse := &pb.ResolveActionsResponse{}
	s.cfg.Log.Log(ctx, "falling back to dotcom to resolve actions", kvp.Int("gh.launch.actions_count", len(actions)))

	var err error
	var token *tokens.AccessToken
	if s.cfg.ResolverTokenFactory != nil {
		token, err = s.cfg.ResolverTokenFactory.GetToken(ctx)
	}

	// Return back internal server errors for resolving actions if
	// we fail to retrieve the access token from dotcom
	if err != nil {
		return s.buildTwirpErrorResponse(ctx, actions, err)
	}

	resolveActionsWithDotcomClient, err := s.cfg.InternalClientFactory.CreateConnectClient(token)
	if err != nil {
		return s.buildTwirpErrorResponse(ctx, actions, err)
	}

	var (
		wg        sync.WaitGroup
		actionsCh = make(chan *pb.ResolvedAction, len(actions))
		errorsCh  = make(chan *pb.ResolvedActionError, len(actions))
	)

	for _, action := range actions {
		action := action

		s.cfg.Log.Debug(ctx, "attempting to resolve action",
			kvp.String("gh.launch.action_name", action.Name),
			kvp.String("gh.launch.action_version", action.Version),
			kvp.Bool("gh.launch.fallback_to_dotcom", true),
			kvp.Int64("gh.launch.workflow_run.id", workflowRunID),
			kvp.String("gh.launch.job.id", jobID),
			kvp.Uint64("gh.launch.workflow_repository.id", uint64(wfRepoID)),
		)

		wg.Add(1)
		go func() {
			defer wg.Done()
			resolvedAction, err := resolveActionsWithDotcomClient.ResolveAction(ctx, action.Name, types.GitRef(action.Version), 0, "", uint64(wfRepoID))
			if err != nil {
				errMsg := fmt.Sprintf("Internal server error occurred while resolving %q", action.NameWithVersion())

				errorsCh <- &pb.ResolvedActionError{
					Action:  action,
					Message: errMsg,
				}
			} else {
				err = s.cfg.GithubTwirpClient.RetireNamespace(ctx, action.Name)
				if err != nil {
					s.cfg.Log.Error(ctx, "failed to retire namespace of action resolved through dotcom on proxima", kvp.Err(err),
						kvp.String("gh.launch.action_name", action.Name),
						kvp.Bool("gh.launch.fallback_to_dotcom", true))
				}

				actionsCh <- restResolvedActionToDeployerProto(resolvedAction, action, token)
			}
		}()
	}

	wg.Wait()
	close(actionsCh)
	close(errorsCh)

	for resolveErr := range errorsCh {
		s.cfg.Log.Error(ctx, resolveErr.GetMessage(), kvp.String("gh.launch.action_name_version", resolveErr.Action.NameWithVersion()), kvp.Err(err))
		// Send Datadog metric so we can track the number of errors and alert on it
		s.cfg.Stats.Counter(ctx, "resolve_gh_api_actions_error_count", nil, 1)
		resolvedActionsResponse.Errors = append(resolvedActionsResponse.Errors, resolveErr)
	}

	for resolvedAction := range actionsCh {
		s.cfg.Stats.Counter(ctx, "resolve_gh_api_actions_success_count", nil, 1)
		s.cfg.Log.Debug(ctx, "successfully resolved action",
			kvp.String("gh.launch.action_name", resolvedAction.Action.Name),
			kvp.String("gh.launch.action_version", resolvedAction.Action.Version),
			kvp.Bool("gh.launch.fallback_to_dotcom", true),
			kvp.String("gh.launch.resolved_action.name", resolvedAction.ResolvedName))
		resolvedActionsResponse.Actions = append(resolvedActionsResponse.Actions, resolvedAction)
	}

	return resolvedActionsResponse, nil
}

func (s *service) buildTwirpErrorResponse(ctx context.Context, actions []*pb.ActionReference, err error) (*pb.ResolveActionsResponse, error) {
	// If we're hitting the Twirp rate limit, we need to return the error as a "top-level" error so the runner
	// does not handle it as a user error. Everything in `resolveActionErrResp.Errors` is treated as a user error.
	if terrors.IsRateLimitError(err) {
		err := twirp.NewError(twirp.ResourceExhausted, "Calls from Launch to Dotcom are being rate limited")
		s.cfg.Log.Error(ctx, "Launch rate limited while resolving actions", kvp.Err(err))
		s.cfg.Stats.Counter(ctx, "non_retryable_rate_limit_error", nil, 1)
		return nil, err
	}

	resolveActionErrResp := &pb.ResolveActionsResponse{}
	for _, action := range actions {
		errMsg := fmt.Sprintf("Internal server error occurred while resolving %q", action.NameWithVersion())

		s.cfg.Log.Error(ctx, errMsg, kvp.String("gh.launch.action_name_version", action.NameWithVersion()), kvp.Err(err))

		resolveActionErrResp.Errors = append(resolveActionErrResp.Errors, &pb.ResolvedActionError{
			Action:  action,
			Message: errMsg,
		})
	}
	return resolveActionErrResp, nil
}

func (s *service) handleInaccessibleInternalActionRepos(ctx context.Context, inaccessibleRepos []string) (*pb.ResolveActionsResponse, error) {
	docURLPath := "/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#allowing-access-to-components-in-an-internal-repository"
	docsURL := utils.GetGHECDocsURL(docURLPath)
	if s.IsEnterprise {
		docsURL = utils.GetGHESDocsURL(docURLPath, s.EnterpriseVersion)
	}

	inaccessibleReposErrMsg := fmt.Sprintf("Cannot access repositories '%s'.", strings.Join(inaccessibleRepos, ", "))
	errMsg := fmt.Sprintf("Unable to resolve actions. %s Enable access using Settings in the Action repository. See %s for more information.", inaccessibleReposErrMsg, docsURL)
	s.cfg.Log.Log(ctx, "authz validation check failed for some actions")
	return &pb.ResolveActionsResponse{Errors: []*pb.ResolvedActionError{{Message: errMsg}}}, nil
}

func (s *service) buildRedirectedActionsErrorResponse(ctx context.Context, redirectedActions []string) *pb.ResolveActionsResponse {
	errMsg := "Unable to resolve action. Repository not found: %s"
	if len(redirectedActions) > 1 {
		errMsg = "Unable to resolve actions: Repositories not found: %s"
	}

	resolvedErrMessage := fmt.Sprintf(errMsg, strings.Join(redirectedActions, ","))
	s.cfg.Log.Error(ctx, resolvedErrMessage)
	return &pb.ResolveActionsResponse{Errors: []*pb.ResolvedActionError{
		{
			Message: resolvedErrMessage,
		},
	}}
}

func (s *service) collectPrivateAndInternalActionsUsageStats(ctx context.Context, arePrivateActionsAllowed, isNonEnterpriseRepo bool, internalActionsCount, privateAndInternalActionsCount int64) {
	if isNonEnterpriseRepo {
		s.cfg.Stats.Counter(ctx, "resolve_private_actions_count", statter.Tags{"type": "non_enterprise_private_repo"}, privateAndInternalActionsCount)
		return
	}

	s.cfg.Stats.Counter(ctx, "resolve_internal_actions_count", nil, internalActionsCount)
	if arePrivateActionsAllowed {
		s.cfg.Stats.Counter(ctx, "resolve_private_actions_count", statter.Tags{"type": "enterprise_private_repo"}, privateAndInternalActionsCount-internalActionsCount)
	}
}

// For GHES and Proxima, these are the set of actions that we won't try and fetch
// via GH Connect / Actions Proxima integrations app if we don't find them on the local instance
func (s *service) prepareLocalOnlyActionsMap(actionsPolicyInfo *ghtwirp.ActionsPolicyInfo) map[string]bool {
	localOnlyActionsMap := make(map[string]bool)

	if s.IsEnterprise || s.cfg.ResolverTokenFactory != nil {
		for _, localOnlyAction := range actionsPolicyInfo.LocalOnlyActions {
			localOnlyActionsMap[localOnlyAction] = true
		}
	}

	return localOnlyActionsMap
}

// Determines if we should fallback to dotcom resolve a specific action. We fallback when
// i) Launch runs in an GHES instance or a Proxima stamp
// ii) The actions policy setup in gh/gh allows us to refer a non local version of the action
// iii) The action can't be found with the twirp endpoint within the GHES instance/Proxima stamp
func (s *service) shouldFallbackToDotcomToResolveAction(action *pb.ActionReference, resolveActionsErr *ghtwirp.ResolveActionsErr, localOnlyActionsMap map[string]bool) bool {
	return (s.IsEnterprise || s.cfg.ResolverTokenFactory != nil) &&
		!localOnlyActionsMap[action.NameWithVersion()] &&
		resolveActionsErr.MatchesStatusCode(http.StatusNotFound)
}

func (r *ActionRepository) buildActionNameWithVersion() string {
	if len(r.Path) > 0 {
		return fmt.Sprintf("%s/%s@%s", r.Name, r.Path, r.Ref)
	}
	return fmt.Sprintf("%s@%s", r.Name, r.Ref)
}

// Parse an ActionNameWithVersion and returns the Nwo, Path, Ref
//
// parseNameWithVersion("org/repo/.github/actions/test-action@main") => "org/repo", ".github/actions/test-action", "main", nil
func parseNameWithVersion(actionNameWithVersion string) (string, string, string, error) {
	parts := strings.Split(actionNameWithVersion, "@")
	if len(parts) != 2 {
		return "", "", "", errors.Errorf("Invalid actionNameWithVersion (%s)", actionNameWithVersion)
	}

	nameParts := strings.Split(parts[0], "/")
	if len(nameParts) < 2 {
		return "", "", "", errors.Errorf("Invalid actionNameWithVersion (%s)", actionNameWithVersion)
	}

	return fmt.Sprintf("%s/%s", nameParts[0], nameParts[1]), strings.Join(nameParts[2:], "/"), parts[1], nil
}

func isPrivateOrInternal(visibility string) bool {
	return isInternal(visibility) || isPrivate(visibility)
}

func isInternal(visibility string) bool {
	return RepositoryVisibilityValue[visibility] == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_INTERNAL
}

func isPrivate(visibility string) bool {
	return RepositoryVisibilityValue[visibility] == ghactions.RepositoryVisibility_REPOSITORY_VISIBILITY_PRIVATE
}

func isInternalRepository(resolvedAction *ghactions.ResolvedAction) bool {
	return isInternal(resolvedAction.Visibility) && resolvedFromRepository(resolvedAction)
}

func isPrivateOrInternalRepository(resolvedAction *ghactions.ResolvedAction) bool {
	return isPrivateOrInternal(resolvedAction.Visibility) && resolvedFromRepository(resolvedAction)
}

func resolvedFromRepository(resolvedAction *ghactions.ResolvedAction) bool {
	// For backwards compatibility and to ensure that we don't break existing request flows, we'll assume that this
	// field being invalid/missing means that the action was resolved from a repository, since that was the previous default.
	// This can be removed once the immutable actions feature is fully rolled out and all servers populate this field correctly.
	return resolvedAction.ResolveStrategy == ghactions.ResolveStrategy_RESOLVE_STRATEGY_REPOSITORY ||
		resolvedAction.ResolveStrategy == ghactions.ResolveStrategy_RESOLVE_STRATEGY_INVALID
}

func twirpResolvedActionToDeployerProto(action *ghactions.ResolvedAction, reference *pb.ActionReference, token *tokens.AccessToken) *pb.ResolvedAction {
	resp := &pb.ResolvedAction{
		Action:       reference,
		ResolvedName: action.ResolvedName,
		ResolvedSha:  action.ResolvedSha,
		TarUrl:       action.TarUrl,
		ZipUrl:       action.ZipUrl,
	}

	if token != nil {
		resp.Authentication = &pb.ResolvedActionAuthentication{
			Token:     token.Token,
			ExpiresAt: timestamppb.New(token.Expiry),
		}
	}

	if action.PackageVersion != "" && action.PackageManifestDigest != "" {
		resp.PackageDetails = &pb.ResolvedActionPackageDetails{
			Version:        action.PackageVersion,
			ManifestDigest: action.PackageManifestDigest,
		}
	}

	return resp
}

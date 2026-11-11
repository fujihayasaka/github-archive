package twirpserver

import (
	"context"
	"fmt"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/sandbox"
	"github.com/github/sweagentd/internal/sweagentd"
	jobs_pb "github.com/github/sweagentd/proto/jobs/v1"
	sweagentdTwirp "github.com/github/sweagentd/proto/sweagentd/v1"
	"github.com/twitchtv/twirp"
	"golang.org/x/sync/errgroup"
)

// agentComputeTokenPermissions are the GitHub App permissions requested when
// minting a user-to-server token for agent compute environments.
var agentComputeTokenPermissions = map[string]string{
	"contents":      "write",
	"issues":        "write",
	"pull_requests": "write",
	"workflows":     "write",
	"metadata":      "read",
	"actions":       "read",
}

type agentComputeSetupData struct {
	repoNWO    string
	repoConfig *sweagentdTwirp.ConfigurationForRepositoryResponse
	token      string
	ownerType  sweagentd.OwnerType
}

// CreateAgentCompute provisions a compute environment, sets it up, and launches the Copilot CLI.
// Currently backed by GitHub Sandbox VMs via the sandbox service.
func (s *Server) CreateAgentCompute(ctx context.Context, req *jobs_pb.CreateAgentComputeRequest) (*jobs_pb.CreateAgentComputeResponse, error) {
	ctx, span := s.obsv.Tracer.Start(ctx, "twirpserver.CreateAgentCompute")
	defer span.End()

	if req.ActorId == 0 {
		return nil, twirp.RequiredArgumentError("actor_id")
	}
	if req.AgentId == 0 {
		return nil, twirp.RequiredArgumentError("agent_id")
	}
	// repository_id is optional. When provided, repository_owner_id must
	// also be provided so the sandbox can be tagged with its owner. When
	// omitted, scope_id is required so the user-to-server token can still
	// be scoped to an installation.
	if req.RepositoryId != 0 && req.RepositoryOwnerId == 0 {
		return nil, twirp.RequiredArgumentError("repository_owner_id")
	}
	if req.RepositoryId == 0 && req.ScopeId == 0 {
		return nil, twirp.RequiredArgumentError("scope_id")
	}

	// Repos on the copilot_swe_agent_disallow list are blocked from
	// provisioning agent compute environments. Matches the monolith's
	// RepoEligibilityChecker, which treats the flag as a hard repo-level gate.
	if s.ffClient.IsEnabledForRepo(ctx, featureflags.CopilotSWEAgentDisallow, int64(req.RepositoryId)) {
		return nil, twirp.PermissionDenied.Error("repository is not allowed to use the coding agent")
	}

	setup, err := s.fetchAgentComputeSetupData(ctx, req)
	if err != nil {
		return nil, err
	}

	// When no repository is attached we couldn't derive ownerType from the
	// repository's installation. Fall back to resolving scope_id via the
	// REST API: GET /user/:id returns either a User or Organization actor.
	if setup.ownerType == "" && req.ScopeId != 0 {
		ownerType, lookupErr := s.resolveScopeOwnerType(ctx, req.AgentId, req.ScopeId, setup.token)
		if lookupErr != nil {
			return nil, twirp.InternalErrorWith(goerrors.Errorf("failed to resolve scope owner type: %w", lookupErr))
		}
		setup.ownerType = ownerType
	}

	params := &sandbox.CreateSandboxParams{
		RepositoryID:      req.RepositoryId,
		RepositoryOwnerID: req.RepositoryOwnerId,
		RepositoryNWO:     setup.repoNWO,
		BranchName:        req.BranchName,
		ActorID:           req.ActorId,
		AgentID:           req.AgentId,
		ProblemStatement:  req.ProblemStatement,
		EnvironmentVariables: map[string]string{
			"GITHUB_COPILOT_API_TOKEN": setup.token,
			"GITHUB_COPILOT_GIT_TOKEN": setup.token,
			"GITHUB_TOKEN":             setup.token,
			"REMOTE_JSON_RPC":          "true",
		},
		CLIFlags:                req.CliFlags,
		FirewallEnabled:         setup.repoConfig.GetIsFirewallEnabled(),
		FirewallUseDefaultRules: setup.repoConfig.GetShouldFirewallUseDefaultRules(),
		FirewallAllowedRules:    setup.repoConfig.GetFirewallAllowedRules(),
		BillableOwnerID:         req.ScopeId,
		BillableOwnerType:       string(setup.ownerType),
	}
	if req.Resources != nil {
		params.CPU = req.Resources.Cpu
		params.Memory = req.Resources.Memory
	}
	if req.Lifecycle != nil {
		params.Lifecycle = &sandbox.LifecycleParams{
			AutoSuspendEnabled:        req.Lifecycle.AutoSuspendEnabled,
			AutoSuspendIdleTimeoutMin: req.Lifecycle.AutoSuspendIdleTimeoutMin,
			SuspendMode:               req.Lifecycle.SuspendMode,
			AutoDeleteAfterMin:        req.Lifecycle.AutoDeleteAfterMin,
		}
	}

	result, err := s.sandboxService.CreateSandbox(ctx, params)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to create agent compute")
		return nil, twirp.NewError(twirp.Internal, "failed to create agent compute")
	}

	return &jobs_pb.CreateAgentComputeResponse{
		ComputeId: result.SandboxID,
	}, nil
}

func (s *Server) fetchAgentComputeSetupData(ctx context.Context, req *jobs_pb.CreateAgentComputeRequest) (*agentComputeSetupData, error) {
	var data agentComputeSetupData

	eg, gctx := errgroup.WithContext(ctx)
	if req.RepositoryId != 0 {
		eg.Go(func() error {
			repo, err := s.ghTwirp.GetRepoById(gctx, int64(req.RepositoryId))
			if err != nil {
				return twirp.NewError(twirp.NotFound, fmt.Sprintf("repository %d not found", req.RepositoryId))
			}
			data.repoNWO = fmt.Sprintf("%s/%s", repo.GetOwnerLogin(), repo.GetName())
			return nil
		})
		eg.Go(func() error {
			var err error
			data.repoConfig, err = s.ghTwirp.SweagentdAPI().ConfigurationForRepository(gctx, &sweagentdTwirp.ConfigurationForRepositoryRequest{
				RepositoryId: int64(req.RepositoryId),
				UserId:       req.ActorId,
				AgentId:      req.AgentId,
			})
			if err != nil {
				return twirp.InternalErrorWith(goerrors.Errorf("failed to fetch repository configuration: %w", err))
			}
			return nil
		})
	}
	eg.Go(func() error {
		mintReq := &sweagentdTwirp.MintUserToServerTokenForReposRequest{
			UserId:  req.ActorId,
			AgentId: req.AgentId,
			ScopeId: req.ScopeId,
		}
		if req.RepositoryId != 0 {
			mintReq.Repositories = []*sweagentdTwirp.RepositoryScope{{
				RepositoryId: req.RepositoryId,
				Permissions:  agentComputeTokenPermissions,
			}}
		} else {
			// Installation-wide scope: per-repo permissions don't apply, so
			// pass the requested permissions at the top level.
			mintReq.Permissions = agentComputeTokenPermissions
		}
		tokenResp, err := s.ghTwirp.SweagentdAPI().MintUserToServerTokenForRepos(gctx, mintReq)
		if err != nil {
			return twirp.InternalErrorWith(goerrors.Errorf("failed to mint token: %w", err))
		}
		data.token = tokenResp.Token
		return nil
	})
	eg.Go(func() error {
		if req.RepositoryId == 0 {
			// No repository attached: there's no repository installation to
			// look up. Leave ownerType unset; callers should treat the empty
			// value as "unknown" rather than relying on a repo-derived
			// User/Organization classification.
			return nil
		}
		info, err := s.ghTwirp.GetInstallationInfo(gctx, req.AgentId, int64(req.RepositoryId))
		if err != nil {
			return twirp.InternalErrorWith(goerrors.Errorf("failed to fetch installation info: %w", err))
		}
		data.ownerType = info.OwnerType
		return nil
	})
	err := eg.Wait()
	if err != nil {
		return nil, err
	}
	return &data, nil
}

// resolveScopeOwnerType resolves the User/Organization type of scope_id by
// calling the REST endpoint GET /user/:id, which transparently returns
// either kind of actor. Used when no repository is attached and we cannot
// derive owner type from the repository's installation.
func (s *Server) resolveScopeOwnerType(ctx context.Context, agentID int64, scopeID uint64, token string) (sweagentd.OwnerType, error) {
	app, err := s.appProvider.FindByID(ctx, agentID)
	if err != nil {
		return "", goerrors.Errorf("failed to find agent %d: %w", agentID, err)
	}
	gh := s.ghf.NewClientForUser(token, scopeID, app)
	user, err := gh.GetUserByID(ctx, scopeID)
	if err != nil {
		return "", goerrors.Errorf("failed to get user %d: %w", scopeID, err)
	}
	switch user.GetType() {
	case "Organization":
		return sweagentd.OwnerTypeOrganization, nil
	case "User":
		return sweagentd.OwnerTypeUser, nil
	default:
		return "", goerrors.Errorf("unexpected user type %q for scope %d", user.GetType(), scopeID)
	}
}

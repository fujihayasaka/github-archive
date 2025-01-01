package token

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/github/go-kvp"
	empty "github.com/golang/protobuf/ptypes/empty"
	errs "github.com/pkg/errors"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy/token"
	terrors "github.com/github/launch/types/errors"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workflowbuild"
)

type service struct {
	log           logger.Logger
	stats         statter.Statter
	buildRepo     deployer.WorkflowBuildsRepositoryReadOnly
	tokenFactory  workflowbuild.TokenFactory
	isMultitenant bool
}

func New(log logger.Logger, statter statter.Statter, buildRepo deployer.WorkflowBuildsRepositoryReadOnly, tokenFactory workflowbuild.TokenFactory, isMultitenant bool) *service {
	return &service{
		log:           log,
		stats:         statter,
		buildRepo:     buildRepo,
		tokenFactory:  tokenFactory,
		isMultitenant: isMultitenant,
	}
}

func (s *service) GetToken(ctx context.Context, req *pb.GetTokenRequest) (*pb.GetTokenResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	resp, err := s.handleGetTokenRequest(ctx, req)
	if err != nil {
		span.RecordError(err)

		// launch-receiver uses twirp to call GetToken, so return a twirp.Error
		if terrors.IsNotFoundError(err) {
			return nil, twirp.NotFoundError(err.Error())
		}
		s.log.Report(ctx, errors.New("Failed to get token"), kvp.Err(err))
		return nil, twirp.InternalError("Could not get token")
	}

	return resp, nil
}

func (s *service) RefreshToken(ctx context.Context, req *pb.RefreshTokenRequest) (*pb.RefreshTokenResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	resp, err := s.handleRefreshTokenRequest(ctx, req)
	if err != nil {
		s.log.Report(ctx, errors.New("Failed to refresh token"), kvp.Err(err))
		span.RecordError(err)
		if strings.Contains(err.Error(), "invalid installation token") {
			return nil, svcerr.NewInternalError("Could not refresh token: invalid installation token")
		}

		return nil, svcerr.NewInternalError("Could not refresh token")
	}

	return resp, nil
}

func (s *service) RevokeToken(ctx context.Context, req *pb.RevokeTokenRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	err := s.handleRevokeTokenRequest(ctx, req)
	if err != nil {
		s.log.Report(ctx, errors.New("Failed to revoke token"), kvp.Err(err))
		span.RecordError(err)
		return nil, svcerr.NewInternalError("Could not revoke token")
	}

	return &empty.Empty{}, nil
}

func (s *service) GetJobPermissions(ctx context.Context, req *pb.GetJobPermissionsRequest) (*pb.GetJobPermissionsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	resp, err := s.handleGetJobPermissionsRequest(ctx, req)
	if err != nil {
		s.log.Report(ctx, errors.New("Failed to get job permissions"), kvp.Err(err))
		span.RecordError(err)
		return nil, svcerr.NewInternalError("Could not get job permissions")
	}

	return resp, nil
}

func (s *service) handleRefreshTokenRequest(ctx context.Context, req *pb.RefreshTokenRequest) (*pb.RefreshTokenResponse, error) {
	buildState, ok, err := s.buildRepo.GetDataForTokenRequest(ctx, req.GetWorkflowId())
	if err != nil {
		return nil, errs.Wrap(err, "Error looking up token data for workflow")
	}
	if !ok {
		return nil, errs.New("No token data returned for workflow")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", buildState.RepositoryID.String()))

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.isMultitenant {

		if buildState.GitHubTenantID == nil {
			return nil, errs.New("GitHub tenant id in workflow build state must not be nil")
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *buildState.GitHubTenantID, s.isMultitenant)
		if err != nil {
			return nil, errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state")
		}
	}

	accessToken := tokens.AccessToken{
		Token: req.GetToken(),
	}

	token, err := s.tokenFactory.RefreshToken(ctx, &accessToken)
	if err != nil {
		return nil, errs.Wrap(err, "error refreshing token")
	}

	resp := pb.RefreshTokenResponse{
		Token:     token.Token,
		ExpiresAt: timestamppb.New(token.Expiry),
	}

	return &resp, nil
}

func (s *service) handleRevokeTokenRequest(ctx context.Context, req *pb.RevokeTokenRequest) error {
	buildState, ok, err := s.buildRepo.GetDataForTokenRequest(ctx, req.GetWorkflowId())
	if err != nil {
		return errs.Wrap(err, "Error looking up token data for workflow")
	}
	if !ok {
		return errs.New("No token data returned for workflow")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", buildState.RepositoryID.String()))

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.isMultitenant {

		if buildState.GitHubTenantID == nil {
			return errs.New("GitHub tenant id in workflow build state must not be nil")
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *buildState.GitHubTenantID, s.isMultitenant)
		if err != nil {
			return errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state")
		}
	}

	accessToken := tokens.AccessToken{
		Token: req.GetToken(),
	}

	err = s.tokenFactory.RevokeToken(ctx, buildState.RepositoryID, &accessToken)
	if err != nil {
		return errs.Wrap(err, "error revoking token")
	}

	return nil
}

func (s *service) handleGetTokenRequest(ctx context.Context, req *pb.GetTokenRequest) (*pb.GetTokenResponse, error) {
	buildState, ok, err := s.buildRepo.GetDataForTokenRequest(ctx, req.GetWorkflowId())
	if err != nil {
		return nil, errs.Wrap(err, "Error looking up token data for workflow")
	}
	if !ok {
		return nil, errs.New("No token data returned for workflow")
	}
	if buildState.TokenPermissions == nil {
		return nil, errs.New("No permissions set, token can't be requested")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", buildState.RepositoryID.String()))

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.isMultitenant {

		if buildState.GitHubTenantID == nil {
			return nil, errs.New("GitHub tenant id in workflow build state must not be nil")
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *buildState.GitHubTenantID, s.isMultitenant)
		if err != nil {
			return nil, errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state")
		}
	}

	tokenPermissions, extendedPermissions, err := s.tokenFactory.CalculateJobPermissions(
		ctx, s.log, buildState.TokenPermissions, req.Permissions, buildState.WorkflowRunID, req.GetWorkflowRunPermissions(),
	)
	if err != nil {
		return nil, errs.Wrap(err, "Error while calculating job permissions")
	}
	s.log.Debug(
		ctx,
		"Calculated permissions for job",
		kvp.Any("gh.launch.default_permissions", buildState.TokenPermissions.DefaultPermissions),
		kvp.Any("gh.launch.request_permissions", req.Permissions),
		kvp.String("gh.launch.issued_permissions", fmt.Sprint(permsAsMap(*tokenPermissions))),
		kvp.Any("gh.launch.extended_permissions", extendedPermissions),
	)

	token, err := s.tokenFactory.NewToken(ctx, buildState.RepositoryID, tokenPermissions, extendedPermissions)
	if err != nil {
		return nil, errs.Wrap(err, "Error generating token with permissions")
	}

	// Note: this is not returning extended permissions (per-PR permissions).
	// Actions Service prints the list of permissions in trace logs and user logs
	resp := pb.GetTokenResponse{
		Token:       token.Token,
		ExpiresAt:   timestamppb.New(token.Expiry),
		Permissions: permsAsMap(token.Permissions),
	}

	return &resp, nil
}

func (s *service) handleGetJobPermissionsRequest(ctx context.Context, req *pb.GetJobPermissionsRequest) (*pb.GetJobPermissionsResponse, error) {
	buildState, ok, err := s.buildRepo.GetDataForTokenRequest(ctx, req.GetPlanId())
	if err != nil {
		return nil, errs.Wrap(err, "Error looking up token data for workflow")
	}
	if !ok {
		return nil, errs.New("No token data returned for workflow")
	}
	if buildState.TokenPermissions == nil {
		return nil, errs.New("No permissions set on workflow build")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", buildState.RepositoryID.String()))

	// GitHubTenantID will be a nil pointer for non-multi-tenant modes.
	if s.isMultitenant {

		if buildState.GitHubTenantID == nil {
			return nil, errs.New("GitHub tenant id in workflow build state must not be nil")
		}

		ctx, err = ghtenant.ContextWithTenantID(ctx, *buildState.GitHubTenantID, s.isMultitenant)
		if err != nil {
			return nil, errs.Wrap(err, "expected valid GitHub tenant id to be set in workflow build state")
		}
	}

	tokenPermissions, _, err := s.tokenFactory.CalculateJobPermissions(
		ctx, s.log, buildState.TokenPermissions, req.RequestedPermissions, buildState.WorkflowRunID, nil,
	)
	if err != nil {
		return nil, errs.Wrap(err, "Error while calculating job permissions")
	}
	s.log.Debug(
		ctx,
		"Determined effective permissions for job without minting token",
		kvp.Any("gh.launch.default_permissions", buildState.TokenPermissions.DefaultPermissions),
		kvp.Any("gh.launch.request_permissions", req.RequestedPermissions),
		kvp.Any("gh.launch.issued_permissions", tokenPermissions),
	)

	// Note: this is not returning extended permissions (per-PR permissions).
	resp := pb.GetJobPermissionsResponse{
		EffectivePermissions: permsAsMap(*tokenPermissions),
	}

	return &resp, nil
}

func permsAsMap(perms tokens.InstallationPermissions) map[string]string {
	val := map[string]string{}

	if perms.Actions != "" {
		val["Actions"] = string(perms.Actions)
	}
	if perms.Attestations != "" {
		val["Attestations"] = string(perms.Attestations)
	}
	if perms.Checks != "" {
		val["Checks"] = string(perms.Checks)
	}
	if perms.Contents != "" {
		val["Contents"] = string(perms.Contents)
	}
	if perms.Deployments != "" {
		val["Deployments"] = string(perms.Deployments)
	}
	if perms.Issues != "" {
		val["Issues"] = string(perms.Issues)
	}
	if perms.Discussions != "" {
		val["Discussions"] = string(perms.Discussions)
	}
	if perms.Metadata != "" {
		val["Metadata"] = string(perms.Metadata)
	}
	if perms.Packages != "" {
		val["Packages"] = string(perms.Packages)
	}
	if perms.Pages != "" {
		val["Pages"] = string(perms.Pages)
	}
	if perms.PullRequests != "" {
		val["PullRequests"] = string(perms.PullRequests)
	}
	if perms.RepositoryProjects != "" {
		val["RepositoryProjects"] = string(perms.RepositoryProjects)
	}
	if perms.Statuses != "" {
		val["Statuses"] = string(perms.Statuses)
	}
	if perms.SecurityEvents != "" {
		val["SecurityEvents"] = string(perms.SecurityEvents)
	}
	return val
}

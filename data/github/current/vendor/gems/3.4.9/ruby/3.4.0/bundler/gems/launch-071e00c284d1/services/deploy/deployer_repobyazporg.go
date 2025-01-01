package deploy

import (
	"context"

	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	pb "github.com/github/launch/services/pb/deploy"
)

func (s *service) RepoByAZPTenant(ctx context.Context, req *pb.RepoByAZPTenantRequest) (*pb.RepoByAZPTenantResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	azpResource, found, err := s.cfg.AZPResourcesLoader.GetByTenantName(ctx, req.GetName())
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	if !found {
		return nil, tracing.RecordError(span, svcerr.NewNotFoundError("tenant %q not found", req.GetName()))
	}

	repoID := azpResource.EntityID

	_, repoDatabaseID, err := repoID.Decode()
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	owners, err := s.cfg.GithubTwirpClient.GetRepositoryOwners(ctx, repoDatabaseID)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	client, err := s.cfg.ClientFactory.NewClientForRepositoryOwner(ctx, repoID, owners.Owner.GlobalID)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	nwo, err := client.RepositoryNWO(ctx, repoID)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInternalError(err.Error()))
	}

	return &pb.RepoByAZPTenantResponse{
		RepositoryId: repoID.String(),
		Env:          azpResource.Environment,
		Nwo:          nwo.String(),
	}, nil
}

package deploy

import (
	"context"
	"sync"

	"github.com/github/go-kvp"
	"github.com/golang/protobuf/ptypes/empty"
	"github.com/hashicorp/go-multierror"
	"github.com/pkg/errors"
	errs "github.com/pkg/errors"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	pb "github.com/github/launch/services/pb/deploy"
	"github.com/github/launch/types"
)

// ReportAdminEventForOwnerRepos let actions service know that a certain admin event happened to all repositories of an owner along with some metadata, ex: the user is marked as spammy.
func (s *service) ReportAdminEventForOwnerRepos(ctx context.Context, req *pb.ReportAdminEventForOwnerReposRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ownerGID := types.NewGlobalID(ctx, req.GetOwnerGlobalId())
	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.owner.global_id", ownerGID.String()),
		kvp.Int64("gh.launch.owner.global_id", req.GetOwnerId()),
		kvp.String("gh.launch.admin_event", req.GetAdminEvent()),
	)

	// query all repositories
	s.cfg.Log.Debug(ctx, "attempting to get all repositories of the owner")
	repositories, err := s.cfg.GithubTwirpClient.GetRepositories(ctx, req.GetOwnerId())
	if err != nil {
		return &empty.Empty{}, errors.Wrap(err, "error loading repositories for owner")
	}

	multiErrs := &multierror.Error{}
	var wg sync.WaitGroup
	var errorsCh = make(chan error, len(repositories))
	s.cfg.Log.Debug(ctx, "owner repositories count", kvp.Int("gh.launch.owner_repositories.count", len(repositories)))

	for _, repo := range repositories {
		repoGID := types.NewGlobalID(ctx, repo.GetGlobalRelayId())
		wg.Add(1)
		go func(ctx context.Context, repoRelayId types.GlobalID, repoName string) {
			ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", repoRelayId.String()))

			s.cfg.Log.Debug(ctx, "attempting to notify azp repository with the admin_event for owner")
			data := map[string]string{
				"owner":  req.GetOwnerName(),
				"repo":   repoName,
				"reason": req.GetData(),
			}

			err := s.cfg.AdminEventsReporter.ReportRepoAdminEvent(ctx, repoRelayId, req.GetAdminEvent(), data)

			if err != nil {
				s.cfg.Log.Report(ctx, err)
				errorsCh <- errs.Wrapf(err, "error report admin event for repository: %s", repoRelayId)
			} else {
				s.cfg.Log.Debug(ctx, "successfully report admin event for owner to AZP")
			}
			wg.Done()
		}(ctx, repoGID, repo.GetName())
	}

	wg.Wait()
	close(errorsCh)
	for err := range errorsCh {
		multiErrs = multierror.Append(multiErrs, err)
	}

	return &empty.Empty{}, multiErrs.ErrorOrNil()
}

// ReportAdminEventForBillingOwner let actions service know that a certain admin event happened to a billing owner (user/org/enterprise) along with some metadata, ex: the user is deleted.
func (s *service) ReportAdminEventForBillingOwner(ctx context.Context, req *pb.ReportAdminEventForBillingOwnerRequest) (*empty.Empty, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ownerGID := types.NewGlobalID(ctx, req.GetOwnerGlobalId())
	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.owner.global_id", ownerGID.String()),
		kvp.String("gh.launch.admin_event", req.GetAdminEvent()),
	)

	err := s.cfg.AdminEventsReporter.ReportBillingOwnerAdminEvent(ctx, ownerGID, req.GetOwnerName(), req.GetAdminEvent(), req.GetData())
	if err != nil {
		s.cfg.Log.Report(ctx, err)
		return &empty.Empty{}, tracing.RecordError(span, err)
	}

	s.cfg.Log.Debug(ctx, "successfully report admin event for billing owner to AZP")
	return &empty.Empty{}, nil
}

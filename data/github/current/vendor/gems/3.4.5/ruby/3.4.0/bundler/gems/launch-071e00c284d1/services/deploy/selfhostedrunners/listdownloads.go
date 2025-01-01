package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"

	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

// ListRunnerExecutables returns a list of runners
func (s *service) ListDownloads(ctx context.Context, req *ListDownloadsRequest) (*ListDownloadsResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "listdownloads")

	rid := s.getRepositoryGlobalIDFromListDownloadsRequest(ctx, req)
	if rid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repository id cannot be nil")
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.repo.global_id", rid.String()))

	arc, err := s.getAzureRepositoryClient(ctx, rid)
	if err != nil {
		if _, ok := errors.Cause(err).(*deployer.GetAzpResourcesError); ok {
			obs.Log(ctx, "no backing resources for ListDownloads")
			return &ListDownloadsResponse{Downloads: make([]*Download, 0)}, nil
		}
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	downloads, err := arc.ListDownloads(ctx)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	var ds []*Download
	for _, d := range downloads {
		os, err := d.GetOS()
		if err != nil {
			obs.Report(ctx, err)
			continue
		}
		arch, err := d.GetArchitecture()
		if err != nil {
			obs.Report(ctx, err)
			continue
		}
		newd := &Download{
			Type:          d.Type,
			Platform:      d.Platform,
			Version:       d.Version.String(),
			DownloadUrl:   d.DownloadURL,
			Filename:      d.Filename,
			Os:            os,
			Architecture:  arch,
			DownloadToken: d.DownloadToken,
			Sha256Hash:    d.Sha256Hash,
		}
		ds = append(ds, newd)
	}
	return &ListDownloadsResponse{Downloads: ds}, nil
}

func (s *service) getRepositoryGlobalIDFromListDownloadsRequest(ctx context.Context, req *ListDownloadsRequest) types.GlobalID {
	return types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
}

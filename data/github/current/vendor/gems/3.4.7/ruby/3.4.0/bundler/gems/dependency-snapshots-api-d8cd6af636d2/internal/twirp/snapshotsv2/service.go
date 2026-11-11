package snapshotsv2

import (
	"context"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	protov2 "github.com/github/dependency-snapshots-api/pkg/proto/v2"
	"github.com/github/go-stats"
	"github.com/twitchtv/twirp"
)

// service holds the methods for our Twirp Server as well as a few dependencies.
type service struct {
	statter stats.Client
}

// CreateTwirpServer creates a new TwirpServer instance that adheres to DependenciesService's API.
func CreateTwirpServer(hooks *twirp.ServerHooks, statter stats.Client) proto.TwirpServer {
	service := CreateService(statter)
	return protov2.NewSnapshotsServer(service, hooks)
}

// CreateService creates a new proto.DependenciesService.
func CreateService(statter stats.Client) protov2.Snapshots {
	service := &service{
		statter: statter,
	}

	return service
}

func (s *service) AsyncCreateSnapshot(ctx context.Context, req *protov2.AsyncCreateSnapshotRequest) (*protov2.AsyncCreateSnapshotResponse, error) {

	contextlogger.Info(ctx, "AsyncCreateSnapshot")

	payload := req.GetSnapshotPayload()
	if len(payload) == 0 {
		return nil, twirp.RequiredArgumentError("snapshot_payload")
	}

	return nil, twirp.NewError(twirp.Unimplemented, "AsyncCreateSnapshot is not implemented yet")
}

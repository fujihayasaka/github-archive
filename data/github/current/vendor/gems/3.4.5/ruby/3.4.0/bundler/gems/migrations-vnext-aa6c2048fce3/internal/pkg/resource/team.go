package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type team struct {
	baseHandler
	pb             *v1.Team
	key            keys.TeamKey
	importedResult *octov1.ImportTeamResponse
}

var _ handler = (*team)(nil)

func newTeam(pb *v1.Team, logger log.Logger) *team {
	return &team{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (t *team) resourceID() string {
	return t.pb.ResourceId
}

func (t *team) dependencies() (*transformedDeps, error) {
	k, err := keys.ToTeamKey(t.pb.ResourceId)
	if err != nil {
		return nil, fmt.Errorf("could not parse team key: %w", err)
	}
	t.key = k
	deps := newTransformedDeps()
	deps.int64Deps.Add(k.OrganizationKey.String())
	if t.pb.ParentTeamResourceId != "" {
		deps.int64Deps.Add(t.pb.ParentTeamResourceId)
	}
	return deps, nil
}

func (t *team) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	req := &octov1.ImportTeamRequest{
		TargetOrgId:     resolved[t.key.OrganizationKey.String()].int64Val,
		TeamName:        t.pb.Name,
		TeamDescription: wrapperspb.String(t.pb.Description),
		Visibility:      t.pb.Visibility,
	}
	if t.pb.ParentTeamResourceId != "" {
		req.ParentTeamId = wrapperspb.Int64(resolved[t.pb.ParentTeamResourceId].int64Val)
	}

	res, err := importer.ImportTeam(ctx, req)
	if err != nil {
		t.logger.WithError(err).Error("failed to import team", kvp.Any("request", req))
		return fmt.Errorf("failed to load team: %w", err)
	}

	t.importedResult = res
	return nil
}

func (t *team) newResolvedIDs() resolvedIDsByResource {
	return resolvedIDsByResource{
		t.resourceID(): &transformedValues{
			int64Val: t.importedResult.Id,
		},
	}
}

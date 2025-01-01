package processor

import (
	"context"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/pkg/errors"
	"golang.org/x/exp/maps"
)

type Flipper interface {
	IsEnabled(ctx context.Context, feature, actorID string) (bool, error)
	IsGloballyEnabled(ctx context.Context, feature string) (bool, error)
}

// ListContributorsAPI includes the only method we need from CommitsAPI to make stubbing easier
type ListContributorsAPI interface {
	ListContributors(context.Context, *commits.ListContributorsRequest) (*commits.ListContributorsResponse, error)
}

type AqueductClient interface {
	Send(ctx context.Context, j aqueduct.Job, opts ...aqueduct.SendOption) (string, error)
	QueueDepth(ctx context.Context, app, queue string) (int64, error)
}

type Deps struct {
	spokesdAPI ListContributorsAPI
}

func NewDependencies(spokesdAPI ListContributorsAPI) *Deps {
	return &Deps{
		spokesdAPI: spokesdAPI,
	}
}

func (d *Deps) GetEmailsFromRefUpdates(ctx context.Context, repositoryID uint64, refUpdates []*githubv1.PostReceive_RefUpdate) ([]*commits.Contributor, error) {
	referenceUpdates := make([]*types.ReferenceUpdate, 0, len(refUpdates))

	for _, refUpdate := range refUpdates {
		referenceUpdates = append(referenceUpdates, &types.ReferenceUpdate{
			Before: &types.ObjectID{
				Id: refUpdate.PreviousRefOid,
			},
			After: &types.ObjectID{
				Id: refUpdate.CurrentRefOid,
			},
			Reference: &types.Reference{
				Name: []byte(refUpdate.RefName),
			},
		})
	}

	contributors := make(map[string]*commits.Contributor)

	var cursor *types.Cursor

	for {
		var resp *commits.ListContributorsResponse

		resp, err := d.spokesdAPI.ListContributors(ctx, &commits.ListContributorsRequest{
			Cursor: cursor,
			Repository: &types.Repository{
				Id:   repositoryID,
				Type: types.Repository_TYPE_REPOSITORY,
			},
			RequestContext: &types.RequestContext{
				// prefer to give up quickly if a repository is hitting internal rate limits
				// rather than adding more load to gitrpcd
				QualityOfService: types.RequestContext_QUALITY_OF_SERVICE_FAIL_FAST,
			},
			Selector: &commits.ListContributorsRequest_PushSelector{
				PushSelector: &selectors.PushSelector{
					ReferenceUpdates: referenceUpdates,
				},
			},
		})
		if err != nil {
			return nil, errors.Wrap(err, "failed calling spokes")
		}

		for _, contributor := range resp.Contributors {
			contributors[string(contributor.EmailBytes)] = contributor
		}

		cursor = resp.GetNextCursor()
		if cursor == nil {
			break
		}
	}

	return maps.Values(contributors), nil
}

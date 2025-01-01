// Package alertlinks handles interactions with alert links.
package alertlinks

import (
	"context"

	"github.com/github/turboscan/ts/appctx"

	"github.com/github/go-http/v2/middleware/requestid"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/pkg/errors"
	"golang.org/x/exp/maps"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/mysql/alertlink"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/transforms"
)

type Service struct {
	alertLinkService *alertlink.Service
	hydroPublisher   HydroPublisher
	es               *elasticsearch.Service
}

type HydroPublisher interface {
	AlertLinksCreateBatch(context.Context, []*tshydro.AlertLinkCreate) error
	AlertLinksUpdateBatch(context.Context, []*tshydro.AlertLinkUpdate) error
}

// NewService returns a new alert links service
func NewService(alertLinkService *alertlink.Service, hydroPublisher HydroPublisher, es *elasticsearch.Service) *Service {
	as := &Service{
		alertLinkService: alertLinkService,
		hydroPublisher:   hydroPublisher,
		es:               es,
	}
	return as
}

func (al *Service) AlertLinks(ctx context.Context, repoID ts.RepositoryEID, logicalAlerts []*ts.LogicalAlert) ([]*ts.AlertLink, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return al.alertLinkService.AlertLinks(ctx, repoID, logicalAlerts)
}

func (al *Service) CountAlertLinkByRef(ctx context.Context, repositoryID ts.RepositoryEID, ref ts.Ref) (uint64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	return al.alertLinkService.CountAlertLinkByRef(ctx, repositoryID, ref)
}

func (al *Service) CreateAlertLinksForAlerts(ctx context.Context, repoID ts.RepositoryEID, logicalAlerts []*ts.LogicalAlert, pullRequestId ts.PullRequestEID, refNameBytes []byte) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	logicalAlertsByID := transforms.IndexBy(logicalAlerts, func(la *ts.LogicalAlert) ts.LogicalAlertID {
		return la.ID
	})

	links := []*ts.AlertLink{}
	for _, la := range logicalAlertsByID {
		links = append(links, &ts.AlertLink{
			RepositoryID:   repoID,
			LogicalAlertID: la.ID,
			AlertNumber:    la.Number,
			PullRequestID:  pullRequestId,
			Ref:            refNameBytes,
		})
	}

	return al.CreateAlertLinks(ctx, repoID, links)
}

func (al *Service) CreateAlertLinks(ctx context.Context, repoID ts.RepositoryEID, links []*ts.AlertLink) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	linksByLogicalAlertID := transforms.IndexBy(links, func(link *ts.AlertLink) ts.LogicalAlertID {
		return link.LogicalAlertID
	})
	logicalAlertIDs := maps.Keys(linksByLogicalAlertID)

	links, err := al.alertLinkService.CreateAlertLinks(ctx, links)
	if err != nil {
		return err
	}

	// Update ElasticSearch index
	updates := map[string]interface{}{
		"has_links": true,
	}
	err = al.es.UpdateAlerts(ctx, repoID, logicalAlertIDs, updates)
	if err != nil {
		// At the moment we just ignore elastic search errors
		appctx.Logger(ctx).WithError(err).Error(
			"Failed to update ES index when adding alert links",
			repoID.AsKVP(),
			kvp.Int("gh.turboscan.ids.count", len(logicalAlertIDs)),
		)

		appctx.Stats(ctx).Counter("es.dynamic_update.error", stats.Tags{"kind": "alert_links"}, 1)
	}

	hydroMessages := make([]*tshydro.AlertLinkCreate, 0, len(links))
	for _, link := range links {
		entity := &tshydro_entities.AlertLink{
			Id:             int64(link.ID),
			RepositoryId:   int64(link.RepositoryID),
			LogicalAlertId: int64(link.LogicalAlertID),
			CreatedAt:      timestamppb.New(link.CreatedAt.Time),
			UpdatedAt:      timestamppb.New(link.UpdatedAt.Time),
			AlertNumber:    int32(link.AlertNumber),
		}

		if link.PullRequestID != 0 {
			entity.PullRequestId = wrapperspb.Int64(int64(link.PullRequestID))
		}
		if len(link.Ref) > 0 {
			entity.Ref = wrapperspb.Bytes(link.Ref)
		}

		hydroMessages = append(hydroMessages, &tshydro.AlertLinkCreate{
			RequestId: requestid.GetGitHubRequestID(ctx),
			AlertLink: entity,
		})
	}

	if err := al.hydroPublisher.AlertLinksCreateBatch(ctx, hydroMessages); err != nil {
		return errors.Wrap(err, "failed to publish Hydro messages")
	}

	return nil
}

func (al *Service) DeleteAlertLinks(ctx context.Context, alertLinks []ts.AlertLinkWithoutID) error {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	// Find the persisted alert links to delete
	alertLinksWithIDs, err := al.alertLinkService.FindAlertLinks(ctx, alertLinks)
	if err != nil {
		return err
	}

	// Fetch the alert link ids
	alertLinkIDs := transforms.Map(alertLinksWithIDs, func(link *ts.AlertLink) ts.AlertLinkID {
		return link.ID
	})

	err = al.alertLinkService.DeleteAlertLinks(ctx, alertLinkIDs)
	if err != nil {
		return err
	}

	return nil
}

func (al *Service) UpdatePRFromRef(ctx context.Context, repositoryID ts.RepositoryEID, ref ts.Ref, pullRequestID ts.PullRequestEID) (int64, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	updatedLinks, err := al.alertLinkService.UpdatePRFromRef(ctx, repositoryID, ref, pullRequestID)
	if err != nil {
		return 0, err
	}

	messages := transforms.Map(updatedLinks, func(link *ts.AlertLink) *tshydro.AlertLinkUpdate {
		entity := tshydro_entities.AlertLink{
			Id:             int64(link.ID),
			RepositoryId:   int64(link.RepositoryID),
			LogicalAlertId: int64(link.LogicalAlertID),
			CreatedAt:      timestamppb.New(link.CreatedAt.Time),
			UpdatedAt:      timestamppb.New(link.UpdatedAt.Time),
		}
		if link.PullRequestID != 0 {
			entity.PullRequestId = wrapperspb.Int64(int64(link.PullRequestID))
		}
		if len(link.Ref) > 0 {
			entity.Ref = wrapperspb.Bytes(link.Ref)
		}
		// AlertNumber is not populated because it is not stored on the alert link

		requestID := requestid.GetGitHubRequestID(ctx)
		var requestIDWrapper *wrapperspb.StringValue
		if len(requestID) > 0 {
			requestIDWrapper = wrapperspb.String(requestID)
		}

		return &tshydro.AlertLinkUpdate{
			RequestId: requestIDWrapper,
			AlertLink: &entity,
		}
	})

	err = al.hydroPublisher.AlertLinksUpdateBatch(ctx, messages)
	if err != nil {
		return 0, errors.Wrap(err, "failed to publish Hydro messages")
	}

	return int64(len(updatedLinks)), nil
}

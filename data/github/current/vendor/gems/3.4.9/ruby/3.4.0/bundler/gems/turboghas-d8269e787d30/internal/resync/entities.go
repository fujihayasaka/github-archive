package resync

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/pkg/errors"
)

type Entity struct {
	ID   uint64
	Type twirpTurboghas.EntityType
}

func toEntityKey(entity interface {
	GetId() uint64
	GetType() twirpTurboghas.EntityType
}) Entity {
	return Entity{
		ID:   entity.GetId(),
		Type: entity.GetType(),
	}
}

func (p *Sync) Entities(ctx context.Context, entities []Entity) (err error) {
	if len(entities) == 0 {
		return nil
	}

	defer func() {
		if err != nil {
			value := make([]string, 0, len(entities))
			for _, entity := range entities {
				value = append(value, fmt.Sprintf("%s(%d)", entity.Type, entity.ID))
			}
			err = fields.Error(err,
				kvp.Strings("gh.turboghas.entities", value),
			)
		}
	}()

	request := &twirpTurboghas.GetEntitiesRequest{}

	for _, entity := range entities {
		request.Entities = append(request.Entities, &twirpTurboghas.GetEntitiesRequest_Entity{
			Id:   entity.ID,
			Type: entity.Type,
		})
	}

	resp, err := p.githubAPI.GetEntities(ctx, request)
	if err != nil {
		return errors.Wrap(err, "failed to get user information")
	}

	found := make(map[Entity]*twirpTurboghas.GetEntitiesResponse_Entity, len(resp.Entities))

	for _, entity := range resp.Entities {
		found[toEntityKey(entity)] = entity
	}

	for _, entity := range request.Entities {
		if _, syncErr := syncEntity(ctx, p.db, toEntityKey(entity), found); syncErr != nil {
			return syncErr
		}
	}

	return nil
}

func syncEntity(ctx context.Context, db *data.Data, key Entity, entities map[Entity]*twirpTurboghas.GetEntitiesResponse_Entity) (found bool, err error) {
	defer func() {
		err = fields.Error(err,
			kvp.Uint64("gh.turboghas.entity_id", key.ID),
			kvp.String("gh.turboghas.entity_type", key.Type.String()),
		)
	}()

	entity, ok := entities[key]
	if !ok {
		return false, errors.Wrap(db.DeleteEntity(ctx, key.ID, key.Type), "failed to delete entity")
	}

	if len(entity.UserIds) == 0 {
		fromctx.Logger.Value(ctx).Warn("organization has no contributors")
	}

	if len(entity.UserIds) > 50*1000 {
		fromctx.Logger.Value(ctx).Warn("organization has large number of contributors", kvp.Int("contributors", len(entity.UserIds)))
	}

	return true, errors.Wrap(db.UpsertEntity(ctx, data.UpsertEntityArgs{
		EntityType: entity.Type,
		EntityID:   entity.Id,
		UserIDs:    entity.UserIds,
	}), "failed to update entity")
}

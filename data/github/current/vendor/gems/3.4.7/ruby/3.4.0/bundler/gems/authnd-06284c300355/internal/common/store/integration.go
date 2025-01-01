package store

import (
	"context"
	"strings"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type IntegrationsStore interface {
	FindIntegrationByID(ctx context.Context, id uint64) (*models.IntegrationWithPreciseOwner, error)
}

func (s *store) FindIntegrationByID(ctx context.Context, id uint64) (*models.IntegrationWithPreciseOwner, error) {
	ctx = mysql.WithQueryTableName(ctx, "integrations")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindIntegrationByID")
	defer span.End()

	var i models.IntegrationWithPreciseOwner
	ex := s.resolver.ReadOnlyExecutorForTable("integrations")
	err := ex.GetContext(
		ctx,
		&i,
		integrationQuery(),
		id,
	)
	if err == nil && i.PreciseOwnerType == "" {
		diagnostics.Statter(ctx).Counter("integrations_find_by_id_no_precise_owner_type", nil, 1)
		// TODO(zacharysierakowski): consider returning an error here based on the stat above
		// err = errors.New("unable to determine the precise owner type")
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "integration_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &i, nil
}

func integrationQuery() string {
	return strings.TrimSpace(`
		SELECT
			i.id, i.owner_id, i.owner_type, i.bot_id, i.name, i.key, i.created_at, i.state, i.user_hidden,

			CASE 
				WHEN i.owner_type = 'User' THEN u.type
				ELSE i.owner_type
			END as precise_owner_type
		
		FROM integrations as i

		LEFT JOIN users as u
		ON (i.owner_id=u.id AND i.owner_type='User')

		WHERE i.id = ?
	`)
}

func (s *enterpriseStore) FindIntegrationByID(ctx context.Context, id uint64) (*models.IntegrationWithPreciseOwner, error) {
	return s.store.FindIntegrationByID(ctx, id)
}

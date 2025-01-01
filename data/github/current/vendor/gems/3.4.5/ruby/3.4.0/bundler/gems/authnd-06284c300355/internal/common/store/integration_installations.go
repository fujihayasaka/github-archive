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

type IntegrationInstallationsStore interface {
	FindIntegrationInstallationByID(ctx context.Context, id uint64) (*models.IntegrationInstallationWithPreciseTargetType, error)
}

func (s *store) FindIntegrationInstallationByID(ctx context.Context, id uint64) (*models.IntegrationInstallationWithPreciseTargetType, error) {
	ctx = mysql.WithQueryTableName(ctx, "integration_installations")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindIntegrationInstallationByID")
	defer span.End()

	var ii models.IntegrationInstallationWithPreciseTargetType
	ex := s.resolver.ReadOnlyExecutorForTable("integration_installations")
	err := ex.GetContext(
		ctx,
		&ii,
		integrationInstallationQuery(),
		id,
	)
	if err == nil && ii.PreciseTargetType == "" {
		diagnostics.Statter(ctx).Counter("integration_installations_find_by_id_no_precise_target_type", nil, 1)
		// TODO(zacharysierakowski): consider returning an error here based on the stat above
		// err = errors.New("unable to determine the precise target type")
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "integration_installation_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &ii, nil
}

func integrationInstallationQuery() string {
	return strings.TrimSpace(`
		SELECT
			ii.id, ii.integration_id, ii.target_id, ii.target_type, ii.user_suspended_by_id, ii.integrator_suspended,

			CASE 
				WHEN ii.target_type = 'User' THEN u.type
				ELSE ii.target_type
			END as precise_target_type
		
		FROM integration_installations as ii

		LEFT JOIN users as u
		ON (ii.target_id=u.id AND ii.target_type='User')

		WHERE ii.id = ?
	`)
}

func (s *enterpriseStore) FindIntegrationInstallationByID(ctx context.Context, id uint64) (*models.IntegrationInstallationWithPreciseTargetType, error) {
	return s.store.FindIntegrationInstallationByID(ctx, id)
}

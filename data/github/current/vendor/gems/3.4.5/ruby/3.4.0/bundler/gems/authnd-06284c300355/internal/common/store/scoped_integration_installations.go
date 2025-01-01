package store

import (
	"context"
	"database/sql"
	"strings"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type ScopedIntegrationInstallationsStore interface {
	FindScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.ScopedIntegrationInstallation, error)
	FindSiteScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.SiteScopedIntegrationInstallationWithPreciseTargetType, error)
}

func (s *store) FindScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.ScopedIntegrationInstallation, error) {
	ctx = mysql.WithQueryTableName(ctx, "scoped_integration_installations")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindScopedIntegrationInstallationByID")
	defer span.End()

	var sii models.ScopedIntegrationInstallation
	ex := s.resolver.ReadOnlyExecutorForTable("scoped_integration_installations")
	err := ex.GetContext(ctx, &sii, `
		SELECT id, integration_installation_id, created_at, updated_at, expires_at
		FROM scoped_integration_installations
		WHERE id = ?
	`, id)

	s.trackFindResult(ctx, ex.ConnectionName(), "scoped_integration_installation_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	return &sii, nil
}

func (s *store) FindSiteScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.SiteScopedIntegrationInstallationWithPreciseTargetType, error) {
	ctx = mysql.WithQueryTableName(ctx, "site_scoped_integration_installations")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindSiteScopedIntegrationInstallationByID")
	defer span.End()

	var ssii models.SiteScopedIntegrationInstallation
	ex := s.resolver.ReadOnlyExecutorForTable("site_scoped_integration_installations")
	err := ex.GetContext(
		ctx,
		&ssii,
		siteScopedIntegrationInstallationQuery(),
		id,
	)
	s.trackFindResult(ctx, ex.ConnectionName(), "site_scoped_integration_installation_by_id", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	// site_scoped_integration_installations is in collab, so we're not able to do a join on `users` to resolve the target type in one query
	preciseTargetType := "Business"
	if ssii.AbstractTargetType == "User" {
		ex = s.resolver.ReadOnlyExecutorForTable("users")
		var userType string
		err = ex.GetContext(
			ctx,
			&userType,
			`SELECT type FROM users WHERE id = ?`,
			ssii.TargetID,
		)
		if err != nil && errors.Is(err, sql.ErrNoRows) {
			diagnostics.Statter(ctx).Counter("site_scoped_integration_installations_user_target_not_found", nil, 1)
			// TODO(zacharysierakowski): consider returning an error here based on the stat above
			// err = errors.New("unable to determine the precise target type")
			err = nil
			userType = ""
		}
		s.trackFindResult(ctx, ex.ConnectionName(), "user_type_by_id", timer, err)
		if err != nil {
			return nil, errors.WithStack(err)
		}
		preciseTargetType = userType
	}

	return &models.SiteScopedIntegrationInstallationWithPreciseTargetType{
		SiteScopedIntegrationInstallation: ssii,
		PreciseTargetType:                 preciseTargetType,
	}, nil
}

func siteScopedIntegrationInstallationQuery() string {
	return strings.TrimSpace(`
		SELECT
			ssii.id, ssii.integration_id, ssii.target_id, ssii.target_type, ssii.created_at, ssii.updated_at, ssii.expires_at		
		FROM site_scoped_integration_installations as ssii
		WHERE ssii.id = ?
	`)
}

func (s *enterpriseStore) FindScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.ScopedIntegrationInstallation, error) {
	return s.store.FindScopedIntegrationInstallationByID(ctx, id)
}

func (s *enterpriseStore) FindSiteScopedIntegrationInstallationByID(ctx context.Context, id uint64) (*models.SiteScopedIntegrationInstallationWithPreciseTargetType, error) {
	return s.store.FindSiteScopedIntegrationInstallationByID(ctx, id)
}

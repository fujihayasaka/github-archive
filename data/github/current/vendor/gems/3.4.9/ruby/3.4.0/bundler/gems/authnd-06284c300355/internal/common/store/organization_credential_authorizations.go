package store

import (
	"context"

	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type OrganizationCredentialAuthorizationsStore interface {
	FindOrganizationSSOByPublicKeyID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error)
	FindOrganizationSSOByOAuthAccessID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error)
}

// FindOrganizationSSOByPublicKeyID finds organization SSO by public Key ID from authnd database.
func (s *store) FindOrganizationSSOByPublicKeyID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	ctx = mysql.WithQueryTableName(ctx, "organization_credential_authorizations")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindOrganizationSSOByPublicKeyID")
	defer span.End()

	ex := s.resolver.ReadOnlyExecutorForTable("organization_credential_authorizations")
	sso, err := s.findOrganizationSSOByTypeAndID(ctx, ex, "PublicKey", credentialID)
	s.trackFindResult(ctx, ex.ConnectionName(), "sso_by_public_key", timer, err)
	if err != nil {
		return nil, err
	}
	return sso, nil
}

// FindOrganizationSSOByOAuthAccessID finds organization SSO by OAuthAccessID from authnd database.
func (s *store) FindOrganizationSSOByOAuthAccessID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	ctx = mysql.WithQueryTableName(ctx, "organization_credential_authorizations")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindOrganizationSSOByOAuthAccessID")
	defer span.End()

	ex := s.resolver.ReadOnlyExecutorForTable("organization_credential_authorizations")
	sso, err := s.findOrganizationSSOByTypeAndID(ctx, ex, "OauthAccess", credentialID)
	s.trackFindResult(ctx, ex.ConnectionName(), "sso_by_oauth_access", timer, err)
	if err != nil {
		return nil, err
	}
	return sso, nil
}

func (s *store) findOrganizationSSOByTypeAndID(ctx context.Context, ex mysql.Executor, credentialType string, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	// This is a helper, called by the "FindOrganizationSSOBy..." functions above, so it's not necessary to trace it separately

	var sso []models.OrganizationCredentialAuthorization
	err := ex.SelectContext(ctx, &sso, `
	SELECT id, organization_id, revoked_at
	FROM organization_credential_authorizations
	WHERE revoked_at IS NULL AND credential_type=? AND credential_id=?`, credentialType, credentialID)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return sso, nil
}

func (s *enterpriseStore) FindOrganizationSSOByPublicKeyID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	return nil, errors.New("not implemented")
}

func (s *enterpriseStore) FindOrganizationSSOByOAuthAccessID(ctx context.Context, credentialID int64) ([]models.OrganizationCredentialAuthorization, error) {
	return nil, errors.New("not implemented")
}

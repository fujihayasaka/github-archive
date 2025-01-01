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

type OAuthAccessesStore interface {
	FindOAuthAccessByHash(ctx context.Context, token string) (*models.OAuthAccessWithTokenContext, error)
}

// FindOAuthAccessByHash finds oauthAccess by hashed token from authnd database.
func (s *store) FindOAuthAccessByHash(ctx context.Context, token string) (*models.OAuthAccessWithTokenContext, error) {
	// this query contains a JOIN between oauth_accesses and oauth_applications, so we just pick one
	ctx = mysql.WithQueryTableName(ctx, "oauth_oauth_applications")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindOAuthAccessByHash")
	defer span.End()

	var access models.OAuthAccessWithTokenContext
	ex := s.resolver.ReadOnlyExecutorForTable("oauth_applications")

	query := makeFindOAuthAccessByHashQuery()
	err := ex.GetContext(ctx, &access, query, token)
	if err == nil && (access.HasApplication() && !access.HasValidApplicationOwner()) {
		diagnostics.Statter(ctx).Counter("oauth_accesses_find_by_hash_invalid_application_owner", nil, 1)
		// TODO(zacharysierakowski): consider returning an error here based on the stat above
		// err = errors.New("did not find a valid application owner for the oauth access")
	}
	s.trackFindResult(ctx, ex.ConnectionName(), "oauth_by_token", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}
	return &access, nil
}

func makeFindOAuthAccessByHashQuery() string {
	return strings.TrimSpace(`
		SELECT
			o.id, o.user_id, o.application_id, o.code, o.raw_data, o.created_at,
			o.description, o.accessed_at, o.hashed_token, o.token_last_eight,
			o.fingerprint, o.authorization_id, o.application_type, o.expires_at_timestamp,
			o.installation_id, o.installation_type, o.last_issued_at,

			CASE 
				WHEN o.application_type = 'OauthApplication' THEN IF(oa.state = 1, true, false)
				WHEN o.application_type = 'Integration' THEN IF(i.state = 1, true, false)
				ELSE NULL
			END as application_suspended,

			CASE 
				WHEN o.application_type = 'OauthApplication' THEN oa.key
				WHEN o.application_type = 'Integration' THEN i.key
				ELSE NULL
			END as application_key,

			CASE 
				WHEN o.application_type = 'OauthApplication' THEN oa.user_id
				WHEN o.application_type = 'Integration' THEN i.owner_id
				ELSE NULL
			END as application_owner_id,

			CASE 
				WHEN o.application_type = 'OauthApplication' THEN ou.type
				WHEN o.application_type = 'Integration' AND i.owner_type = 'User' THEN iu.type
				WHEN o.application_type = 'Integration' AND i.owner_type = 'Business' THEN 'Business'
				ELSE NULL
			END as application_owner_type,

			CASE
				WHEN o.application_type = 'OauthApplication' THEN ou.spammy
				WHEN o.application_type = 'Integration' AND i.owner_type = 'User' THEN iu.spammy
				WHEN o.application_type = 'Integration' AND i.owner_type = 'Business' THEN ib.spammy
				ELSE NULL
			END as application_owner_spammy

		FROM oauth_accesses AS o

		LEFT JOIN oauth_applications AS oa
		ON (o.application_id=oa.id AND o.application_type='OauthApplication')
		LEFT JOIN users as ou
		ON (oa.user_id=ou.id AND o.application_type='OauthApplication')

		LEFT JOIN integrations AS i
		ON (o.application_id=i.id AND o.application_type='Integration')
		LEFT JOIN users as iu
		ON (i.owner_id=iu.id AND o.application_type='Integration' AND i.owner_type='User')
		LEFT JOIN businesses as ib
		ON (i.owner_id=ib.id AND o.application_type='Integration' AND i.owner_type='Business')

		WHERE hashed_token=?
		LIMIT 1
	`)
}

func (s *enterpriseStore) FindOAuthAccessByHash(ctx context.Context, token string) (*models.OAuthAccessWithTokenContext, error) {
	return nil, errors.New("not implemented")
}

package store

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/authnd/internal/api/tenancy"
	"github.com/github/authnd/internal/common"
	"github.com/github/authnd/internal/common/diagnostics"
	"github.com/github/authnd/internal/common/models"
	"github.com/github/authnd/internal/common/store/mysql"
	"github.com/github/authnd/internal/common/tracing"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type PublicKeysStore interface {
	FindPublicKeyBySHA256Fingerprint(ctx context.Context, fingerprint string) (*models.PublicKey, error)
}

// FindPublicKeyBySHA256Fingerprint finds SSH public key from authnd db.
func (s *store) FindPublicKeyBySHA256Fingerprint(ctx context.Context, fingerprint string) (*models.PublicKey, error) {
	ctx = mysql.WithQueryTableName(ctx, "public_keys")

	timer := stats.NewTimer(diagnostics.Statter(ctx))
	ctx, span := tracing.ChildSpan(ctx, "store.FindPublicKeyBySHA256Fingerprint")
	defer span.End()

	if s.isProxima {
		tenant := tenancy.GetTenantContext(ctx)
		fingerprint = fmt.Sprintf("%s_%s", fingerprint, tenant.Shortcode)
	}

	var publicKeys []models.PublicKey
	var err error
	ex := s.resolver.ReadOnlyExecutorForTable("public_keys")

	err = ex.SelectContext(ctx, &publicKeys,
		"SELECT id, `key`, title, read_only, verified_at, user_id, repository_id, fingerprint_sha256 FROM public_keys WHERE fingerprint_sha256 = ?",
		fingerprint)

	if err == nil {
		if len(publicKeys) == 0 {
			err = sql.ErrNoRows
		} else if len(publicKeys) > 1 {
			err = common.StoreErrUnexpectedMultipleResults
		}
	}

	s.trackFindResult(ctx, ex.ConnectionName(), "public_key_by_fingerprint", timer, err)
	if err != nil {
		return nil, errors.WithStack(err)
	}

	key := publicKeys[0]
	return &key, nil
}

func (s *enterpriseStore) FindPublicKeyBySHA256Fingerprint(ctx context.Context, fingerprint string) (*models.PublicKey, error) {
	return nil, errors.New("not implemented")
}

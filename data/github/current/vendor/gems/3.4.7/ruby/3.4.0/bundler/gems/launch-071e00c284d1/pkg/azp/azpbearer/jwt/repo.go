package jwt

import (
	"context"
	"crypto/rsa"
	"crypto/x509"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/pkg/errors"

	"github.com/github/launch/keystore"
	"github.com/github/launch/observability/tracing"
)

type ProviderForRepoClient struct {
	keystore    keystore.Store
	environment string // environment is needed to create the *keystore.scope
}

func NewProviderForRepoClient(keystore keystore.Store, environment string) *ProviderForRepoClient {
	return &ProviderForRepoClient{
		keystore:    keystore,
		environment: environment,
	}
}

func (rf *ProviderForRepoClient) NewProvider(tenantName string, encryptedPrivateKey []byte) Provider {
	return &provider{
		timeNow: defaultTimeNow,
		trustSrc: func(ctx context.Context) (*rsa.PrivateKey, *x509.Certificate, error) {
			ctx, span := tracing.Start(ctx)
			defer span.End()

			scope, err := keystore.NewScope(rf.environment, tenantName)
			if err != nil {
				return nil, nil, tracing.RecordError(span, errors.Wrap(err, "creating keystore scope"))
			}
			key, err := rf.keystore.DecryptPrivateKeyForOrganization(ctx, scope, encryptedPrivateKey)
			if err != nil {
				return nil, nil, tracing.RecordError(span, errors.Wrap(err, "decrypting key"))
			}
			return key, nil, nil
		},
		jwtBuilder: func(requestURL, clientID string, _ *x509.Certificate, timeNow func() time.Time) *jwt.Token {
			return getBaseToken(requestURL, clientID, nil, timeNow)
		},
	}
}

package jwt

import (
	"context"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/x509"
	"encoding/hex"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/workflowbuild/azp/config"
)

func ForTokenSvcS2SFrom(cfg config.AzureProviderConfig) Provider {
	return &provider{
		timeNow: defaultTimeNow,
		trustSrc: func(ctx context.Context) (*rsa.PrivateKey, *x509.Certificate, error) {
			return cfg.TokenServicePrivateKey, nil, nil
		},
		jwtBuilder: func(requestURL, _ string, _ *x509.Certificate, timeNow func() time.Time) *jwt.Token {
			return tokenS2SJWTBuilder(requestURL, cfg.ServicePrincipalID, cfg.TokenServiceCert, timeNow)
		},
	}
}

func ForGHAppTokenFrom(cfg config.AzureProviderConfig, certHook CertHook) Provider {
	return &provider{
		timeNow: defaultTimeNow,
		trustSrc: func(ctx context.Context) (*rsa.PrivateKey, *x509.Certificate, error) {
			if cfg.GHAppCert != nil {
				certHook(ctx, cfg.GHAppCert)
			}
			return cfg.GHAppPrivateKey, cfg.GHAppCert, nil
		},
		//nolint:gocritic
		jwtBuilder: func(requestURL, clientID string, cert *x509.Certificate, timeNow func() time.Time) *jwt.Token {
			return aadS2SJWTBuilder(requestURL, clientID, cert, timeNow) // GHAppID
		},
	}
}

type CertHook func(context.Context, *x509.Certificate)
type CertPurpose string

const (
	ForKeyVault             CertPurpose = "keyvault"
	ForS2S                  CertPurpose = "s2s"
	CertRotationMetricEvent             = "hours_until_cert_expiration"
)

func CertificateRotationEmitter(obs *observability.Observability, purpose CertPurpose) CertHook {
	return func(ctx context.Context, cert *x509.Certificate) {
		// sha1 is being used below only for hashing and logging.
		certSha := sha1.Sum(cert.Raw)
		fingerprint := strings.ToUpper(hex.EncodeToString(certSha[:]))
		obs.Statter.Gauge(ctx, CertRotationMetricEvent, statter.Tags{"cert_fingerprint": fingerprint, "purpose": string(purpose)}, int64(time.Until(cert.NotAfter).Hours()))
	}
}

package jwt

import (
	"context"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"os"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/utils"
	"github.com/github/launch/workflowbuild/azp/config"
)

const (
	testURL        = "http://github.com"
	testClientID   = "1234"
	testResource   = "test"
	testTenantName = "tenant"
)

func Test_jwtBuilders(t *testing.T) {
	cert, key, err := genCerts()
	require.NoError(t, err)
	now := time.Now()
	timeNow := func() time.Time { return now }

	repoProviderFactory := NewProviderForRepoClient(nil, "")

	type wantClaims struct {
		aud, iss, sub string
		nbf, exp      int64
	}

	defaultWantClaims := wantClaims{
		aud: testURL,
		iss: testClientID,
		sub: testClientID,
		nbf: now.Unix(),
		exp: now.Add(jwtDuration).Unix(),
	}

	type wantHeader struct {
		x5cPresent, x5tPresent bool
	}

	var expectedX5C = []string{
		base64.StdEncoding.EncodeToString(cert.Raw),
	}

	certSha := sha1.Sum(cert.Raw)
	var expectedX5T = base64.URLEncoding.EncodeToString(certSha[:])

	tests := []struct {
		name       string
		wantClaims wantClaims
		wantHeader wantHeader
		provider   Provider
	}{
		{
			name: "ForTokenSvcS2SFrom",
			provider: ForTokenSvcS2SFrom(config.AzureProviderConfig{
				TokenServicePrivateKey: key,
				ServicePrincipalID:     testClientID,
				TokenServiceCert:       cert,
			}),
			wantClaims: defaultWantClaims,
			wantHeader: wantHeader{
				x5cPresent: true,
			},
		},
		{
			name: "ForAADS2SFrom",
			provider: ForGHAppTokenFrom(config.AzureProviderConfig{
				GHAppPrivateKey: key,
				GHAppCert:       cert,
			}, func(ctx context.Context, c *x509.Certificate) {}),
			wantClaims: defaultWantClaims,
			wantHeader: wantHeader{
				x5cPresent: true,
				x5tPresent: true,
			},
		},
		{
			name:       "RepoJWTProvider",
			provider:   repoProviderFactory.NewProvider(testTenantName, nil),
			wantClaims: defaultWantClaims,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			internalProvider := (tt.provider).(*provider)
			j := internalProvider.jwtBuilder(testURL, testClientID, cert, timeNow)

			// Claims are configured as expected
			claims := (j.Claims).(jwt.MapClaims)
			require.Equal(t, tt.wantClaims.aud, claims["aud"])
			require.Equal(t, tt.wantClaims.iss, claims["iss"])
			require.Equal(t, tt.wantClaims.sub, claims["sub"])
			require.Equal(t, tt.wantClaims.nbf, claims["nbf"])
			require.Equal(t, tt.wantClaims.exp, claims["exp"])

			header := j.Header

			x5c, ok := header["x5c"]
			if tt.wantHeader.x5cPresent {
				require.True(t, ok, "no x5c header found")
				require.Equal(t, expectedX5C, x5c)

			} else {
				require.False(t, ok, "unexpected x5c header found")
			}

			x5t, ok := header["x5t"]
			if tt.wantHeader.x5tPresent {
				require.True(t, ok, "no x5t header found")
				require.Equal(t, expectedX5T, x5t)
			} else {
				require.False(t, ok, "unexpected x5t header found")
			}
		})
	}
}

// genCerts will perform the task of creating a temporary Certificate and Key.
func genCerts() (*x509.Certificate, *rsa.PrivateKey, error) {
	testCert, err := os.ReadFile("../../../../config/dev/root.pem")
	if err != nil {
		return nil, nil, errors.Wrap(err, "reading cert file")
	}
	certPEM := utils.UnescapeConsulKVString(string(testCert))
	block, _ := pem.Decode([]byte(certPEM))
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, nil, errors.Wrap(err, "decoding certificate")
	}

	testKey, err := os.ReadFile("../../../../config/dev/root.key")
	if err != nil {
		return nil, nil, errors.Wrap(err, "reading rsa key file")
	}
	keyPEM := utils.UnescapeConsulKVString(string(testKey))
	key, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(keyPEM))

	if err != nil {
		return nil, nil, errors.Wrap(err, "parsing private key")
	}

	return cert, key, nil
}

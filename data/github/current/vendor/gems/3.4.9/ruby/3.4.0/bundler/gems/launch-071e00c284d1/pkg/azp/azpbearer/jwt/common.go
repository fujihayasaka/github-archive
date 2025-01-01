package jwt

import (
	"crypto/sha1"
	"crypto/x509"
	"encoding/base64"
	"net/url"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
)

const (
	jwtDuration = time.Minute * 5
)

var defaultTimeNow = time.Now

// getBaseToken is used by all jwt builders, but is suitable on its own for
// repo scoped JWT tokens.
func getBaseToken(requestURL, clientID string, _ *x509.Certificate, timeNow func() time.Time) *jwt.Token {
	return jwt.NewWithClaims(
		jwt.SigningMethodRS256,
		jwt.MapClaims{
			"jti": uuid.New().String(),
			"aud": requestURL,
			"exp": timeNow().Add(jwtDuration).Unix(),
			"nbf": timeNow().Unix(),
			"iss": clientID,
			"sub": clientID,
		},
	)
}

// tokenS2SJWTBuilder builds a jwt that will be authorized by Actions' Token Service and
// is suitable for S2S within Actions.
func tokenS2SJWTBuilder(requestURL, clientID string, cert *x509.Certificate, timeNow func() time.Time) *jwt.Token {
	token := getBaseToken(requestURL, clientID, nil, timeNow)

	certificateChain := []string{
		base64.StdEncoding.EncodeToString(cert.Raw),
	}
	token.Header["x5c"] = certificateChain

	return token
}

// aadS2SJWTBuilder builds a jwt that will be authorized by Azure Active Directory (AAD) and
// is suitable for S2S within Actions as well as with Azure Key Vault.
func aadS2SJWTBuilder(requestURL, clientID string, cert *x509.Certificate, timeNow func() time.Time) *jwt.Token {
	token := getBaseToken(requestURL, clientID, nil, timeNow)

	certSha := sha1.Sum(cert.Raw)
	base64Fingerprint := base64.URLEncoding.EncodeToString(certSha[:])
	token.Header["x5t"] = base64Fingerprint

	certificateChain := []string{
		base64.StdEncoding.EncodeToString(cert.Raw),
	}
	token.Header["x5c"] = certificateChain

	return token
}

func getData(clientID, jwt, resource string) url.Values {
	data := url.Values{}
	data.Set("grant_type", "client_credentials")
	data.Set("client_assertion", jwt)
	data.Set("client_id", clientID)
	data.Set("client_assertion_type", "urn:ietf:params:oauth:client-assertion-type:jwt-bearer")

	if resource != "" {
		data.Set("resource", resource)
	}

	return data
}

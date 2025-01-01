package testutils

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"
)

type JWKSServer struct {
	*httptest.Server
	t    *testing.T
	key  *rsa.PrivateKey
	cert *x509.Certificate
	kid  string
}

// NewJWKSServer returns a new httptest.Server that serves a JWKS endpoint and a minted JWT.
// The caller is responsible for closing the server.
func NewJWKSServer(t *testing.T) *JWKSServer {
	t.Helper()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}

	cert := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			Organization: []string{"GitHub"},
			CommonName:   "Test Certificate",
		},
		NotBefore: time.Now(),
		NotAfter:  time.Now().Add(24 * time.Hour),
		KeyUsage:  x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
	}

	certBytes, err := x509.CreateCertificate(rand.Reader, cert, cert, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}

	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: certBytes})
	thumbprint := sha1.Sum(certBytes)

	kid := uuid.NewString()
	pub := key.Public().(*rsa.PublicKey)
	jwks := map[string]any{
		"kid": kid,
		"kty": "RSA",
		"alg": "RS256",
		"e":   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes()),
		"n":   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
		"use": "sig",
		"x5c": []string{base64.StdEncoding.EncodeToString(certPEM)},
		"x5t": base64.RawURLEncoding.EncodeToString(thumbprint[:]),
	}

	tokenServer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/.well-known/jwks" {
			keys := map[string]any{
				"keys": []map[string]any{
					jwks,
				},
			}

			w.Header().Set("Content-Type", "application/json")
			enc := json.NewEncoder(w)
			err = enc.Encode(keys)
			if err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
			}
			return
		}

		w.WriteHeader(http.StatusNotFound)
	}))

	return &JWKSServer{
		Server: tokenServer,
		t:      t,
		key:    key,
		cert:   cert,
		kid:    kid,
	}
}

func (s *JWKSServer) MintToken(runID, jobID, jobName string, issuer string) string {
	s.t.Helper()

	if issuer == "" {
		issuer = s.Server.URL
	}

	token := jwt.NewWithClaims(jwt.SigningMethodRS256, jwt.MapClaims{
		"iss":     issuer,
		"sub":     "test-subject",
		"aud":     "test-audience",
		"ac":      "[{\"Scope\":\"refs/heads/👋\",\"Permission\":3},{\"Scope\":\"refs/heads/main\",\"Permission\":1}]",
		"scp":     fmt.Sprintf("Actions.Runner:%s:%s", runID, jobID),
		"orch_id": fmt.Sprintf("%s.%s.__default", runID, jobName),
		"exp":     time.Now().Add(time.Hour).Unix(),
		"iat":     time.Now().Unix(),
	})
	token.Header["kid"] = s.kid
	signedToken, err := token.SignedString(s.key)
	if err != nil {
		s.t.Fatal(err)
	}

	return signedToken
}

func (s *JWKSServer) JWKSURL() string {
	return s.Server.URL + "/.well-known/jwks"
}

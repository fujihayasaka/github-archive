// Package devsigner implements a TokenSigner that signs OIDC JWTs locally
// using an RSA private key, suitable for development.
package devsigner

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"os"
	"slices"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
	"github.com/google/uuid"

	"github.com/github/sweagentd/internal/goerrors"
)

const (
	defaultTokenExpiry = 5 * time.Minute

	rsaKeySize = 2048
)

// additionalJWTClaims lists the additional claims included in OIDC tokens. No others should be allowed.
var additionalJWTClaims = []string{"repository", "repository_id", "repository_owner", "repository_owner_id", "client_id", "agent_client_id", "agent_id", "installation_id", "preferred_username", "user_id", "scope", "resource", "session_id"}

// Signer generates signed OIDC JWTs for token exchange with integrator endpoints.
type Signer struct {
	signingKey    any
	signingMethod jwt.SigningMethod
	keyID         string
	issuer        string
	tokenExpiry   time.Duration
}

// Option configures optional settings on a Signer.
type Option func(*Signer)

// WithTokenExpiry overrides the default token expiry duration.
func WithTokenExpiry(d time.Duration) Option {
	return func(ti *Signer) {
		ti.tokenExpiry = d
	}
}

// ComputeKeyID derives a deterministic key ID from an RSA public key using a
// truncated SHA-256 hash of the modulus bytes, encoded as base64url.
func ComputeKeyID(pub *rsa.PublicKey) string {
	h := sha256.Sum256(pub.N.Bytes())
	return base64.RawURLEncoding.EncodeToString(h[:16])
}

// NewSigner creates a Signer that signs JWTs with the given key and method.
// The keyID appears in the JWT header as "kid" for key lookup via JWKS.
// The issuer is the "iss" claim value (e.g. the GitHub OIDC issuer URL).
func NewSigner(signingKey any, signingMethod jwt.SigningMethod, keyID, issuer string, opts ...Option) *Signer {
	ti := &Signer{
		signingKey:    signingKey,
		signingMethod: signingMethod,
		keyID:         keyID,
		issuer:        issuer,
		tokenExpiry:   defaultTokenExpiry,
	}
	for _, opt := range opts {
		opt(ti)
	}
	return ti
}

// NewSignerFromKey creates a Signer using the given RSA private key and issuer URL.
// If privateKey is nil a temporary RSA key pair is generated (suitable for development).
func NewSignerFromKey(issuer string, privateKey *rsa.PrivateKey) (*Signer, error) {
	if privateKey == nil {
		var err error
		privateKey, err = rsa.GenerateKey(rand.Reader, rsaKeySize)
		if err != nil {
			return nil, goerrors.Errorf("oidc: failed to generate RSA key: %w", err)
		}
	}

	kid := ComputeKeyID(&privateKey.PublicKey)
	return NewSigner(privateKey, jwt.SigningMethodRS256, kid, issuer), nil
}

// NewDefaultSigner creates a Signer with a default configuration suitable for development.
// It generates a temporary RSA key pair and constructs the issuer URL based on the provided parameters.
func NewDefaultSigner(oidcIssuerURL, copilotAPIURL string, httpPort int) (*Signer, error) {
	issuer := IssuerURL(oidcIssuerURL, copilotAPIURL, httpPort)
	return NewSignerFromKey(issuer, nil)
}

// PublicKey returns the RSA public key corresponding to the signing key.
func (ti *Signer) PublicKey() *rsa.PublicKey {
	if k, ok := ti.signingKey.(*rsa.PrivateKey); ok {
		return &k.PublicKey
	}
	return nil
}

// KeyID returns the key identifier included in JWT headers.
func (ti *Signer) KeyID() string {
	return ti.keyID
}

// Issuer returns the "iss" claim value used in issued tokens.
func (ti *Signer) Issuer() string {
	return ti.issuer
}

// IssueIDToken implements TokenSigner by signing the token locally.
// It sets standard JWT claims including "aud" from audience, "sub" from subject,
// and "act.sub" from actSubject. Additional claims are merged as top-level JWT
// payload keys.
func (ti *Signer) IssueIDToken(_ context.Context, audience, subject, actSubject string, additionalClaims map[string]string) (string, error) {
	// Validate that all keys in additionalClaims are allowed
	for key := range additionalClaims {
		if !slices.Contains(additionalJWTClaims, key) {
			return "", goerrors.Errorf("oidc: claim %q is not in AdditionalJWTClaims", key)
		}
	}

	now := time.Now()

	claims := jwt.MapClaims{
		"iss": ti.issuer,
		"sub": subject,
		"aud": audience,
		"exp": jwt.NewNumericDate(now.Add(ti.tokenExpiry)),
		"iat": jwt.NewNumericDate(now),
		"nbf": jwt.NewNumericDate(now),
		"jti": uuid.NewString(),
		"act": map[string]any{
			"sub": actSubject,
		},
	}

	for k, v := range additionalClaims {
		claims[k] = v
	}

	token := jwt.NewWithClaims(ti.signingMethod, claims)
	token.Header["kid"] = ti.keyID

	signed, err := token.SignedString(ti.signingKey)
	if err != nil {
		return "", goerrors.Errorf("oidc: failed to sign token: %w", err)
	}

	return signed, nil
}

// IssuerURL returns the OIDC issuer URL for the running service.
//
// Resolution order:
//  1. oidcIssuerURL — explicit override from configuration (for the dev signer, typically sourced
//     from the OIDC_DEV_SIGNER_ISSUER_URL environment variable). Used as-is when set.
//  2. Codespaces environment variables (CODESPACE_NAME + port forwarding domain).
//  3. copilotAPIURL — derived from COPILOT_API_URL. Any trailing "/" is stripped.
//  4. http://localhost:{port} fallback for local development.
func IssuerURL(oidcIssuerURL, copilotAPIURL string, httpPort int) string {
	// Override for scenario-based testing
	if oidcIssuerURL != "" {
		return strings.TrimRight(oidcIssuerURL, "/")
	}

	// Development in codespaces - sweagentd port can be made public to allow e2e to work with things like Entra ID
	codespaceName := os.Getenv("CODESPACE_NAME")
	forwardingDomain := os.Getenv("GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN")
	if codespaceName != "" && forwardingDomain != "" {
		return fmt.Sprintf("https://%s-%d.%s", codespaceName, httpPort, forwardingDomain)
	}

	// CAPI url for environments other than development
	if copilotAPIURL != "" {
		return fmt.Sprintf("%s/agents/swe", strings.TrimRight(copilotAPIURL, "/"))
	}

	return fmt.Sprintf("http://localhost:%d", httpPort)
}

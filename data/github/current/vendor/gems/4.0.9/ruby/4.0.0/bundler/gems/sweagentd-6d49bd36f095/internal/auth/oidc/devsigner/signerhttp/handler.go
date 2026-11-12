// Package signerhttp provides HTTP handlers for OIDC discovery endpoints,
// including the OpenID Configuration and JWKS (JSON Web Key Set) endpoints
// that allow integrators to verify tokens issued by sweagentd.
package signerhttp

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"math/big"
	"net/http"

	"github.com/github/sweagentd/internal/auth/oidc/devsigner"
)

// jwkKey represents a single RSA public key in JWK format (RFC 7517).
type jwkKey struct {
	Kty string `json:"kty"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	Kid string `json:"kid"`
	N   string `json:"n"`
	E   string `json:"e"`
}

// jwkSet represents a JSON Web Key Set (RFC 7517 §5).
type jwkSet struct {
	Keys []jwkKey `json:"keys"`
}

// openIDConfiguration represents the minimal OpenID Connect Discovery 1.0
// metadata needed for token verification.
type openIDConfiguration struct {
	Issuer  string `json:"issuer"`
	JWKSURI string `json:"jwks_uri"`
}

// protectedResourceMetadata represents the subset of RFC 9728 metadata served
// by the local dev signer endpoints.
type protectedResourceMetadata struct {
	Resource             string   `json:"resource"`
	AuthorizationServers []string `json:"authorization_servers"`
}

// rsaPublicKeyToJWK converts an RSA public key to a JWK representation.
func rsaPublicKeyToJWK(pub *rsa.PublicKey, kid string) jwkKey {
	return jwkKey{
		Kty: "RSA",
		Use: "sig",
		Alg: "RS256",
		Kid: kid,
		N:   base64.RawURLEncoding.EncodeToString(pub.N.Bytes()),
		E:   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pub.E)).Bytes()),
	}
}

// Handler serves the JWKS and OpenID configuration endpoints.
type Handler struct {
	signer *devsigner.Signer
}

// NewHandler creates a handler that serves OIDC discovery endpoints using the
// signing key metadata from the given TokenSigner.
func NewHandler(signer *devsigner.Signer) *Handler {
	return &Handler{signer: signer}
}

// RegisterRoutes registers the .well-known endpoints on the given router.
// These routes must be registered outside of any authentication middleware.
func (h *Handler) RegisterRoutes(mux interface {
	Get(string, http.HandlerFunc)
}) {
	mux.Get("/.well-known/oauth-protected-resource", h.handleProtectedResourceMeta)
	mux.Get("/.well-known/oauth-protected-resource/public/mcp", h.handleProtectedResourceMeta)
	mux.Get("/.well-known/openid-configuration", h.handleOpenIDConfiguration)
	mux.Get("/.well-known/jwks.json", h.handleJWKS)
}

func (h *Handler) handleProtectedResourceMeta(w http.ResponseWriter, _ *http.Request) {
	metadata := protectedResourceMetadata{
		Resource:             h.signer.Issuer(),
		AuthorizationServers: []string{h.signer.Issuer()},
	}
	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	_ = enc.Encode(metadata) //nolint:errchkjson // best-effort write to HTTP response
}

// handleOpenIDConfiguration serves the OpenID Connect discovery document.
func (h *Handler) handleOpenIDConfiguration(w http.ResponseWriter, _ *http.Request) {
	issuer := h.signer.Issuer()
	cfg := openIDConfiguration{
		Issuer:  issuer,
		JWKSURI: issuer + "/.well-known/jwks.json",
	}

	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	_ = enc.Encode(cfg) //nolint:errchkjson // best-effort write to HTTP response
}

// handleJWKS serves the JSON Web Key Set containing the signing public key.
// When the signer does not expose a local public key (e.g. tokenz-backed),
// an empty key set is returned.
func (h *Handler) handleJWKS(w http.ResponseWriter, _ *http.Request) {
	keys := jwkSet{}
	if pub := h.signer.PublicKey(); pub != nil {
		keys.Keys = []jwkKey{rsaPublicKeyToJWK(pub, h.signer.KeyID())}
	}

	w.Header().Set("Content-Type", "application/json")
	enc := json.NewEncoder(w)
	_ = enc.Encode(keys) //nolint:errchkjson // best-effort write to HTTP response
}

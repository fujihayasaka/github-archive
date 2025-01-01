package tokenauth

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/MicahParks/keyfunc"
	"github.com/golang-jwt/jwt/v4"
	jwtRequest "github.com/golang-jwt/jwt/v4/request"
	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/types"
)

type Verifier interface {
	LaunchReceiverScopesValid(ctx context.Context, workflowRunBackendID, workflowJobRunBackendID string) bool
	GetRunnerTypeClaim(ctx context.Context) string
	GetOwnerIDClaim(ctx context.Context) types.GlobalID
}

type contextKey string

const (
	launchReceiverScopeIdentifier = "Actions.Runner"
	contextKeyRunnerClaims        = contextKey("runnerclaims")
	RunnerTypeHosted              = "hosted"
)

type Client struct {
	issuerJWKS                  map[string]*keyfunc.JWKS
	multiTenantEnterpriseIssuer string
}

// New creates a new auth client
func New(ctx context.Context, cfg *Config, log logger.Logger) (*Client, error) {
	log.Log(ctx, "creating auth client")
	issuerJWKSMap := make(map[string]*keyfunc.JWKS)
	for _, jwksURL := range cfg.JWKSURLs() {
		jwks, err := keyfunc.Get(jwksURL, keyfunc.Options{
			RefreshInterval: cfg.JWKSRefreshInterval,
			RefreshTimeout:  cfg.JWKSTimeout,
			RefreshErrorHandler: func(err error) {
				log.Report(ctx, errors.Wrap(err, "failed to refresh jwks"))
			},
		})
		if err != nil {
			log.Report(ctx, errors.Wrap(err, fmt.Sprintf("failed to create jwks client for %s", jwksURL)))
			continue
		}

		issuerURL, err := url.Parse(jwksURL)
		if err != nil {
			return nil, err
		}

		// use Host instead of HostName because we need port number to be included in the key if the jwks url is a mesh address
		// this is only relevent in multi-tenant mode
		hostName := issuerURL.Host
		// if hostName is "tokenz.actions.localhost", then set map key for "tokenz.tokenz.svc.cluster.local", see https://github.com/github/tokenz/pull/106
		if strings.EqualFold(hostName, "tokenz.actions.localhost") {
			issuerJWKSMap["http://tokenz.tokenz.svc.cluster.local"] = jwks
		} else {
			issuerJWKSMap[issuerURL.Scheme+"://"+hostName] = jwks
			// also add hostname without protocol for vstoken compatibility
			issuerJWKSMap[hostName] = jwks
		}
	}

	if len(issuerJWKSMap) == 0 {
		return nil, errors.New("no jwks issuers found")
	}

	return &Client{
		issuerJWKS:                  issuerJWKSMap,
		multiTenantEnterpriseIssuer: cfg.MultiTenantEnterpriseIssuer,
	}, nil
}

// AuthenticationMiddleware is an http middleware that validates the token and adds claims to the context
func (c *Client) AuthenticationMiddleware(log logger.Logger) func(next http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		fn := func(w http.ResponseWriter, r *http.Request) {
			ctx := r.Context()

			token, err := jwtRequest.AuthorizationHeaderExtractor.ExtractToken(r)
			if err != nil {
				w.WriteHeader(http.StatusUnauthorized)
				log.Error(ctx, "unable to extract token from request", kvp.Err(err))
				return
			}

			tokenResp, err := c.validateToken(token)
			if err != nil || !tokenResp.valid {
				w.WriteHeader(http.StatusUnauthorized)
				log.Error(ctx, "unable to validate token", kvp.Err(err))
				return
			}

			if tokenResp.runnerClaims.OrchestrationId != "" {
				ctx = ctxstash.WithVSSOrchestrationID(ctx, tokenResp.runnerClaims.OrchestrationId)
			}
			r = r.WithContext(context.WithValue(ctx, contextKeyRunnerClaims, tokenResp.runnerClaims))
			next.ServeHTTP(w, r)
		}
		return http.HandlerFunc(fn)
	}
}

// LaunchReceiverScopesValid checks whether the workflow run and workflow job run IDs are attached to the launch receiver scope
func (c *Client) LaunchReceiverScopesValid(ctx context.Context, workflowRunBackendID, workflowJobRunBackendID string) bool {
	claims, ok := ctx.Value(contextKeyRunnerClaims).(*runnerClaims)
	if !ok || claims == nil {
		return false
	}

	return claims.containsScopeValue(launchReceiverScopeIdentifier, fmt.Sprintf("%s:%s", workflowRunBackendID, workflowJobRunBackendID))
}

// GetRunnerTypeClaim returns the runner type claim, which is "hosted", "self-hosted", or "scale-set".
func (c *Client) GetRunnerTypeClaim(ctx context.Context) string {
	claims, ok := ctx.Value(contextKeyRunnerClaims).(*runnerClaims)
	if !ok || claims == nil {
		return ""
	}

	return claims.RunnerType
}

// GetOwnerIDClaim returns the owner ID claim, which is  the global ID of the owner of the workflow repository.
func (c *Client) GetOwnerIDClaim(ctx context.Context) types.GlobalID {
	claims, ok := ctx.Value(contextKeyRunnerClaims).(*runnerClaims)
	if !ok || claims == nil {
		return ""
	}

	return claims.OwnerID
}

type validateTokenResp struct {
	valid        bool
	runnerClaims *runnerClaims
}

func (c *Client) validateToken(tokenString string) (*validateTokenResp, error) {
	token, err := jwt.ParseWithClaims(sanitizeTokenString(tokenString), &runnerClaims{}, c.keyfuncWithClaimsValidation)
	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return &validateTokenResp{valid: false}, nil
	}

	claims, ok := token.Claims.(*runnerClaims)
	if !ok {
		return &validateTokenResp{valid: token.Valid}, nil
	}

	return &validateTokenResp{
		valid:        token.Valid,
		runnerClaims: claims,
	}, nil
}

func (c *Client) keyfuncWithClaimsValidation(token *jwt.Token) (interface{}, error) {
	// validate signing method
	if _, ok := token.Method.(*jwt.SigningMethodRSA); !ok {
		return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
	}

	// validate time-based claims
	if err := token.Claims.Valid(); err != nil {
		return nil, err
	}

	// validate issuer
	claims, ok := token.Claims.(*runnerClaims)
	if !ok {
		return nil, errors.New("error unmarshalling claims")
	}

	// issuer in tokenz proxima is tenant based, e.g., token.actions.github.ghe.com
	var jwks *keyfunc.JWKS
	if launchconfig.IsMultiTenant() && strings.HasSuffix(claims.Issuer, ".ghe.com") {
		jwks, ok = c.issuerJWKS[c.multiTenantEnterpriseIssuer]
		if !ok {
			return nil, fmt.Errorf("unrecognized proxima issuer: %s", claims.Issuer)
		}
	} else {
		jwks, ok = c.issuerJWKS[claims.Issuer]
		if !ok {
			return nil, fmt.Errorf("unrecognized issuer: %s", claims.Issuer)
		}
	}

	if _, ok := token.Header["kid"]; !ok {
		x5t, ok := token.Header["x5t"]
		if !ok {
			return nil, errors.New("missing kid and x5t headers")
		}

		kid, err := convertX5TToKID(x5t.(string))
		if err != nil {
			return nil, err
		}

		// typically modifying the token is not good because the token is validated against the signature
		// however, the since token is parsed prior to this function being called, we can change it without breaking this validation
		// this could break auth if that order ever changes
		token.Header["kid"] = kid
	}

	return jwks.Keyfunc(token)
}

func convertX5TToKID(x5t string) (string, error) {
	// decode x5t
	dst := make([]byte, base64.RawURLEncoding.DecodedLen(len(x5t)))
	n, err := base64.RawURLEncoding.Decode(dst, []byte(x5t))
	if err != nil {
		return "", err
	}

	dst = dst[:n]

	// encode as kid
	return strings.ToUpper(hex.EncodeToString(dst)), nil
}

func sanitizeTokenString(tokenString string) string {
	if strings.HasPrefix(strings.ToLower(tokenString), "bearer") {
		tokenString = tokenString[7:] // removes "Bearer " from the start
	}
	return tokenString
}

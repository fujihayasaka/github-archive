package resolver

import (
	"context"
	"crypto/rsa"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/cenkalti/backoff"
	"github.com/golang-jwt/jwt/v4"
	"github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/clients/github/ratelimit"
	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	errtypes "github.com/github/launch/types/errors"
	"github.com/github/launch/utils"
	"github.com/github/launch/utils/useragent"
)

const (
	// Expire the JWT in just less than 10 minutes to account for drift across servers,
	// because the setting on dotcom is 10 minutes and we've gotten some errors that say
	// `Expiration time' claim ('exp') is too far in the future` (from integration_assertion.rb)
	jwtExpiryTime = (time.Minute * 10) - (time.Second * 10)

	// https://developer.github.com/changes/2016-09-14-Integrations-Early-Access/
	mediaTypeIntegrationPreview = "application/vnd.github.machine-man-preview+json"
)

type TokenFactory interface {
	GetToken(ctx context.Context) (*tokens.AccessToken, error)
}

type resolverAppTokenFactory struct {
	env    string
	cfg    Config
	key    *rsa.PrivateKey
	client *httpclient.Client
	obs    *observability.Observability
}

func NewTokenFactory(env string, cfg Config, http *http.Client, obs *observability.Observability) (TokenFactory, error) {
	if cfg.AppID != 0 && cfg.AppInstallationID != 0 && cfg.AppPrivateKey != "" {
		privateKeyBytes := utils.UnescapeConsulKVBytes([]byte(cfg.AppPrivateKey))
		privateKey, err := jwt.ParseRSAPrivateKeyFromPEM(privateKeyBytes)
		if err != nil {
			return nil, err
		}

		httpClient := httpclient.New(http).WithPkgName("resolver").WithSvcName("tokenFactory")
		return &resolverAppTokenFactory{
			env:    env,
			cfg:    cfg,
			key:    privateKey,
			client: httpClient,
			obs:    obs,
		}, nil
	}
	return nil, nil
}

func (r *resolverAppTokenFactory) GetToken(ctx context.Context) (*tokens.AccessToken, error) {
	ctx, childSpan := tracing.Start(ctx)
	defer childSpan.End()

	r.obs.Log(ctx, "retrieving new access token", kvp.Int64("gh.launch.action_resolver_app.id", r.cfg.AppID), kvp.Int64("gh.launch.action_resolver_app.installation_id", r.cfg.AppInstallationID))

	bearerToken, err := r.newBearerToken()
	if err != nil {
		return nil, err
	}

	url := fmt.Sprintf("https://api.github.com/app/installations/%v/access_tokens", r.cfg.AppInstallationID)
	validator := func(resp *http.Response) (retryable bool, err error) {
		if resp.StatusCode < 200 || resp.StatusCode > 299 {
			return resp.StatusCode >= http.StatusInternalServerError, errtypes.NewHTTPError(resp)
		}

		return false, nil
	}

	// Check for GitHub rate limit responses first
	validator = ratelimit.ResponseValidator(ctx, r.obs, "GetResolverInstallationToken", false, validator)
	opts := r.withDefaultOpts(validator, launchhttp.WithBearerToken(bearerToken))

	var sit *tokens.ScopedInstallationToken
	err = r.client.Do(ctx, "GetResolverInstallationToken", http.MethodPost, url, nil, &sit, opts...)
	if err != nil {
		r.obs.Error(ctx, "failed to request access tokens", kvp.Err(err), kvp.Int64("gh.launch.action_resolver_app.id", r.cfg.AppID), kvp.Int64("gh.launch.action_resolver_app.installation_id", r.cfg.AppInstallationID))
		return nil, errors.Wrap(err, "failed to request access token")
	}

	var expiration time.Time
	if sit.ExpiresAt != nil {
		expiration = *sit.ExpiresAt
	}

	r.obs.Log(ctx, "successfully retrieved access token", kvp.Int64("gh.launch.action_resolver_app.id", r.cfg.AppID), kvp.Int64("gh.launch.action_resolver_app.installation_id", r.cfg.AppInstallationID), kvp.Time("gh.launch.action_resolver_app.token.expires_at", expiration))

	return &tokens.AccessToken{
		Token:       sit.Token,
		Expiry:      expiration,
		Permissions: *sit.Permissions,
	}, nil
}

func (r *resolverAppTokenFactory) withDefaultOpts(validator httpclient.ResponseValidator, auth launchhttp.RequestOption) []httpclient.DoOption {
	opts := []httpclient.DoOption{
		// httpclient.WithBreaker(s.breaker),
		httpclient.WithRetries(validator),
		httpclient.WithRequestErrorProcessor(errorProcessor),
		httpclient.WithRequestOptions(
			auth,
			launchhttp.WithHeaders(map[string]string{
				"User-Agent": useragent.GetUserAgent(r.env),
				"Accept":     mediaTypeIntegrationPreview,
			}),
			func(req *http.Request) error {
				mu.ForwardRequestID(req)
				return nil
			},
		),
	}

	return opts
}

func errorProcessor(err error) error {
	// Don't retry on timeout. We want to avoid further increasing load when the access tokens endpoint when it is slow.
	// And retries can cause Launch to hit secondary rate limits across installations.
	if strings.Contains(err.Error(), "timeout awaiting response headers") {
		return backoff.Permanent(err)
	}

	return err
}

func (r *resolverAppTokenFactory) newBearerToken() (string, error) {
	issuedAt := time.Now().Unix()
	claims := &jwt.RegisteredClaims{
		IssuedAt:  &jwt.NumericDate{Time: time.Unix(issuedAt, 0)},
		ExpiresAt: &jwt.NumericDate{Time: time.Unix(issuedAt+int64(jwtExpiryTime.Seconds()), 0)},
		Issuer:    strconv.FormatInt(r.cfg.AppID, 10),
	}
	token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
	return token.SignedString(r.key)
}

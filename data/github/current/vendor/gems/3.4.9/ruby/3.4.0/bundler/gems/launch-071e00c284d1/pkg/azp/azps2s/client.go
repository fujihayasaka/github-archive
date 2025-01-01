package azps2s

import (
	"bytes"
	"context"
	crypto_rand "crypto/rand"
	"crypto/rsa"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math/rand"
	"net/http"
	"time"

	"github.com/cenkalti/backoff/v4"
	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability/tracing"

	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
	"github.com/github/launch/workflowbuild/azp/config"
)

const (
	pollInitialInterval = time.Second * 2
	pollMaxInterval     = time.Second * 10
	pollTimeout         = time.Minute * 3
	pollMultiplier      = 1.5
)

type Options struct {
	breaker             *circuit.Breaker
	tokenSrc            launchhttp.TokenSource
	pollInitialInterval time.Duration
	pollMaxInterval     time.Duration
	pollTimeout         time.Duration
	pollMultiplier      float64
	hooks               *httpclient.ClientHooks
}

type Option func(*Options)

func WithBreaker(breaker *circuit.Breaker) Option {
	return func(o *Options) {
		o.breaker = breaker
	}
}

func WithTokenSource(tokenSrc launchhttp.TokenSource) Option {
	return func(o *Options) {
		o.tokenSrc = tokenSrc
	}
}

func WithHooks(hooks *httpclient.ClientHooks) Option {
	return func(o *Options) {
		o.hooks = hooks
	}
}

type Client struct {
	http    *httpclient.Client
	options *Options

	ghTwirpClient               ghtwirp.Client
	orgRegion, orgCreateBaseURL string
	pipelineBaseUrls            []string
	rand                        *rand.Rand
}

func New(
	http *httpclient.Client,
	ghTwirpClient ghtwirp.Client,
	cfg config.AzureProviderConfig,
	options ...Option,
) (*Client, error) {

	defaultOptions := &Options{
		breaker:             nil,
		tokenSrc:            nil,
		pollInitialInterval: pollInitialInterval,
		pollMaxInterval:     pollMaxInterval,
		pollTimeout:         pollTimeout,
		pollMultiplier:      pollMultiplier,
	}

	for _, option := range options {
		option(defaultOptions)
	}

	if defaultOptions.hooks != nil {
		http = http.WithHooks(defaultOptions.hooks)
	}

	http = http.WithPkgName("azure")
	http = http.WithSvcName("s2s")

	// seed rand with a cryptographically secure random number generator
	var b [8]byte
	_, err := crypto_rand.Read(b[:])
	if err != nil {
		return nil, errors.Wrap(err, "cannot seed math/rand package with cryptographically secure random number generator")
	}
	r := rand.New(rand.NewSource(int64(binary.LittleEndian.Uint64(b[:]))))

	return &Client{
		http:             http,
		ghTwirpClient:    ghTwirpClient,
		orgRegion:        cfg.OrgRegion,
		orgCreateBaseURL: cfg.OrgCreateBaseURL,
		pipelineBaseUrls: cfg.PipelineBaseUrlsList(),
		options:          defaultOptions,
		rand:             r,
	}, nil
}

func (c *Client) CreateTenantWithResources(
	ctx context.Context,
	globalID, ownerGlobalID types.GlobalID,
	name types.RepositoryFullName,
	key *rsa.PublicKey,
	planName string,
	billingOwnerCreatedAt time.Time,
) (*azptypes.CreationResult, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	res, ts, err := c.createRequest(ctx, globalID, ownerGlobalID, name, key, planName, billingOwnerCreatedAt)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "creating organization"))
	}

	switch res.OperationStatus {
	case "succeeded":
		return responseToResult(res), nil
	case "inProgress":
		err := c.pollResponse(ctx, res.OperationURL, ts)
		if err != nil {
			return nil, tracing.RecordError(span, errors.Wrap(err, "polling org create outcome"))
		}
		return responseToResult(res), nil
	default:
		return nil, tracing.RecordError(span, errors.Errorf("unexpected operation status: %s", res.OperationStatus))
	}
}

func (c *Client) createRequest(
	ctx context.Context,
	globalID, ownerGlobalID types.GlobalID,
	name types.RepositoryFullName,
	key *rsa.PublicKey,
	planName string,
	billingOwnerCreatedAt time.Time,
) (*createOrganizationResponse, launchhttp.TokenSource, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "create"

	urlBuilder := c.prepareURLBuilder()

	bodyBuilder, err := c.prepareBodyBuilder(globalID, ownerGlobalID, name, key, planName, billingOwnerCreatedAt)
	if err != nil {
		return nil, nil, tracing.RecordError(span, errors.Wrap(err, "building body builder"))
	}

	var rbody *createOrganizationResponse

	tokenSource := c.options.tokenSrc

	if c.ghTwirpClient.IsFeatureEnabledForActor(ctx, github.PipelineRoundRobin, globalID) {
		err = c.http.DoWithURLBuilder(
			ctx,
			opname,
			http.MethodPost,
			urlBuilder,
			bodyBuilder, // body builder instead since we need to recompute on retry
			&rbody,
			c.defaultOptions(ctx, tokenSource)...,
		)
		if err == nil {
			return rbody, tokenSource, nil
		}
		return nil, nil, tracing.RecordError(span, err)
	}

	err = c.http.Do(
		ctx,
		opname,
		http.MethodPost,
		c.getURL(),
		bodyBuilder, // body builder instead since we need to recompute on retry
		&rbody,
		c.defaultOptions(ctx, tokenSource)...,
	)

	if err != nil {
		return nil, nil, tracing.RecordError(span, err)
	}

	return rbody, tokenSource, nil
}

func (c *Client) prepareBodyBuilder(globalID, ownerGlobalID types.GlobalID, name types.RepositoryFullName, key *rsa.PublicKey, planName string, billingOwnerCreatedAt time.Time) (httpclient.BodyBuilder, error) {
	githubResourceType, githubResourceID, err := globalID.Decode()
	if err != nil {
		return nil, errors.Wrap(err, "error decoding owner global ID")
	}

	var githubResourceOwnerType string
	var githubResourceOwnerID int64
	var githubResourceOwnerGlobalIDString string
	if !ownerGlobalID.IsZeroValue() {
		githubResourceOwnerGlobalIDString = ownerGlobalID.String()
		githubResourceOwnerType, githubResourceOwnerID, err = ownerGlobalID.Decode()
		if err != nil {
			return nil, errors.Wrap(err, "error decoding owner global ID")
		}
	}

	expBytes, err := intToBytes(key.E)
	if err != nil {
		return nil, errors.Wrap(err, "public key invalid - could not read bytes from exponent")
	}

	var createdAt string
	if !billingOwnerCreatedAt.IsZero() {
		createdAt = billingOwnerCreatedAt.Format(time.RFC3339Nano)
	}

	baseBody := requestBody{
		ProviderID: "github-ci",
		Organization: org{
			PreferredRegion: c.orgRegion,
		},
		Pipeline: pipeline{
			Repository: name.String(),
		},
		ApplicationInputs: inputs{
			// send base64 encoded with padding
			PublicKey: pubKey{
				Modulus:  base64.StdEncoding.EncodeToString(key.N.Bytes()),
				Exponent: base64.StdEncoding.EncodeToString(expBytes.Bytes()),
			},
		},
		GitHubResourceType:          githubResourceType,
		GitHubResourceID:            githubResourceID,
		GitHubResourceGlobalID:      globalID.String(),
		GitHubResourceOwnerType:     githubResourceOwnerType,
		GitHubResourceOwnerID:       githubResourceOwnerID,
		GitHubResourceOwnerGlobalID: githubResourceOwnerGlobalIDString,
		BillingOwnerCreatedAt:       createdAt,
		PlanSKU:                     planName,
	}

	return func() (io.Reader, error) {
		// Generate a new tenant name on each retry
		// See https://github.com/github/c2c-actions-experience/issues/1973
		tenantName, err := getRandomTenantName()
		if err != nil {
			return nil, errors.Wrap(err, "could not generate tenant name")
		}
		baseBody.Organization.Name = tenantName

		jbod, err := json.Marshal(baseBody)
		if err != nil {
			return nil, errors.Wrap(err, "marshaling request body")
		}

		return bytes.NewReader(jbod), nil
	}, nil
}

func (c *Client) prepareURLBuilder() httpclient.URLBuilder {
	return func() (string, error) {
		index := c.rand.Intn(len(c.pipelineBaseUrls))
		return c.getPipelineURL(c.pipelineBaseUrls[index]), nil
	}
}

func (c *Client) pollResponse(ctx context.Context, url string, ts launchhttp.TokenSource) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "poll"
	var opResult *OperationResult
	err := c.http.Do(
		ctx,
		opname,
		http.MethodGet,
		url,
		nil,
		&opResult,
		c.defaultOptions(
			ctx,
			ts,
			httpclient.WithPollOutcome(
				c.options.pollInitialInterval,
				c.options.pollMaxInterval,
				c.options.pollTimeout,
				c.options.pollMultiplier,
				func(i any) (bool, error) {
					opptr, ok := i.(**OperationResult)
					opResult := *opptr
					if !ok {
						return false, backoff.Permanent(errors.New("inspector asserting dst type"))
					}
					return opResult.IsComplete(), nil
				},
			),
		)...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}

func (c *Client) getURL() string {
	return fmt.Sprintf("%s/_apis/pipelines/orgs?api-version=5.1-preview", c.orgCreateBaseURL)
}

func (c *Client) getPipelineURL(pipelineBaseURL string) string {
	return fmt.Sprintf("%s/_apis/pipelines/orgs?api-version=5.1-preview", pipelineBaseURL)
}

func (c *Client) defaultOptions(ctx context.Context, ts launchhttp.TokenSource, options ...httpclient.DoOption) []httpclient.DoOption {
	var doOptions []httpclient.DoOption

	if ts != nil {
		doOptions = append(doOptions, httpclient.WithTokenAuth(ts))
	}

	if c.options.breaker != nil {
		doOptions = append(doOptions, httpclient.WithBreaker(c.options.breaker))
	}

	doOptions = append(doOptions, httpclient.WithRetries(azp.ResponseValidator()))
	doOptions = append(doOptions, httpclient.WithRequestOptions(
		launchhttp.WithADNCorrelationHeaders(ctx),
		launchhttp.WithJSONContentType(),
	))

	return append(doOptions, options...)
}

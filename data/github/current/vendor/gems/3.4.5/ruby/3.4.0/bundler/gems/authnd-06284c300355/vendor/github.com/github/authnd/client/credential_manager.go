package client

import (
	"context"
	"strconv"
	"time"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

// A CredentialManager represents a connection to the Authnd Credential Management service.
// For optimal network performance, use a single CredentialManager for all your application's requests.
// CredentialManager is safe for concurrent use by multiple goroutines.
type CredentialManager interface {
	// IssueToken issues a new token credential.
	IssueToken(context.Context, *pb.IssueTokenRequest, ...RequestOption) (*pb.IssueTokenResponse, error)

	// IssueSignedAuthToken issues a new SAT associated with a user session or ID.
	IssueSignedAuthToken(context.Context, *pb.IssueSignedAuthTokenRequest, ...RequestOption) (*pb.IssueSignedAuthTokenResponse, error)

	// VerifyCredentials verifies that given credentials are valid, working credentials.
	VerifyCredentials(context.Context, *pb.VerifyRequest, ...RequestOption) (*pb.BatchVerifyResponse, error)

	// RevokeCredentials revokes a batch of credentials.
	RevokeCredentials(context.Context, *pb.RevokeRequest, ...RequestOption) (*pb.BatchRevokeResponse, error)

	// FindCredentials finds credentials by the given attributes.
	FindCredentials(context.Context, *pb.FindCredentialsRequest, ...RequestOption) (*pb.FindCredentialsResponse, error)
}

type credentialManager struct {
	twirpClient pb.CredentialManager
	statter     stats.Client
}

// NewCredentialManager creates and returns a CredentialManager with the provided options, or an error if applying any of the options failed.
// If no options are provided, recommended options will be applied.
// For optimal network performance, use a single CredentialManager for all your application's requests.
// CredentialManagers are safe for concurrent use by multiple goroutines.
func NewCredentialManager(addr string, catalogService string, opts ...Option) (CredentialManager, error) {
	if addr == "" {
		return nil, errors.New("must provide a non empty addr")
	}
	if catalogService == "" {
		return nil, errors.New("must provide a non empty catalogService")
	}

	clientOpts := defaultClientOptions()

	// Explicitly disabling retries for credential manager.
	opts = append(opts, WithoutRetries())

	err := applyOptions(clientOpts, opts...)
	if err != nil {
		return nil, errors.Wrap(err, "error applying options")
	}

	statter := clientOpts.Statter.WithTags(stats.Tags{
		catalogServiceDimensionName: catalogService,
		clientVersionDimensionName:  Version,
		serviceDimensionName:        "CredentialManager",
	})

	httpClient := clientOpts.CustomHTTPClient
	if httpClient == nil {
		httpClient = createHTTPClient(clientOpts.HTTPClientOptions, statter)
	}

	// always set the catalog service header and user agent
	httpClient = middleware.ApplyCatalogService(httpClient, catalogService)
	httpClient = middleware.ApplyUserAgent(httpClient, Version)

	return &credentialManager{
		pb.NewCredentialManagerProtobufClient(addr, httpClient),
		statter,
	}, nil
}

// IssueToken issues a new token credential.
func (c *credentialManager) IssueToken(ctx context.Context, req *pb.IssueTokenRequest, opts ...RequestOption) (*pb.IssueTokenResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "IssueToken"}
	defer func() {
		duration := time.Since(start)
		c.statter.Counter(requestsMetric, tags, 1)
		c.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	response, err := c.twirpClient.IssueToken(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()
	return response, nil
}

func (c *credentialManager) IssueSignedAuthToken(ctx context.Context, req *pb.IssueSignedAuthTokenRequest, opts ...RequestOption) (*pb.IssueSignedAuthTokenResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "IssueSignedAuthToken"}
	defer func() {
		duration := time.Since(start)
		c.statter.Counter(requestsMetric, tags, 1)
		c.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	response, err := c.twirpClient.IssueSignedAuthToken(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	return response, nil
}

func (c *credentialManager) VerifyCredentials(ctx context.Context, req *pb.VerifyRequest, opts ...RequestOption) (*pb.BatchVerifyResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "VerifyCredentials"}
	defer func() {
		duration := time.Since(start)
		c.statter.Counter(requestsMetric, tags, 1)
		c.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	response, err := c.twirpClient.VerifyCredentials(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	// Add result counts as stat tags for each result (e.g. { "verified": "2", "unverified": "1" }).
	if response.Responses != nil {
		resultCounts := map[string]int{}
		for _, r := range response.Responses {
			if r.IsVerified {
				resultCounts["verified"]++
			} else {
				resultCounts["unverified"]++
			}
		}
		for r, c := range resultCounts {
			tags[r] = strconv.Itoa(c)
		}
	}

	return response, nil
}

// RevokeCredentials revokes a batch of credentials.
func (c *credentialManager) RevokeCredentials(ctx context.Context, req *pb.RevokeRequest, opts ...RequestOption) (*pb.BatchRevokeResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "RevokeCredentials"}
	defer func() {
		duration := time.Since(start)
		c.statter.Counter(requestsMetric, tags, 1)
		c.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	response, err := c.twirpClient.RevokeCredentials(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	// Add result counts as stat tags for each result (e.g. { "RESULT_SUCCESS": "2", "RESULT_ALREADY_REVOKED": "1" }).
	if response.Responses != nil {
		resultCounts := map[pb.RevokeResponse_Result]int{}
		for _, r := range response.Responses {
			resultCounts[r.Result]++
		}
		for r, c := range resultCounts {
			tags[r.String()] = strconv.Itoa(c)
		}
	}
	return response, nil
}

// FindCredentials finds credentials by the given attributes.
func (c *credentialManager) FindCredentials(ctx context.Context, req *pb.FindCredentialsRequest, opts ...RequestOption) (*pb.FindCredentialsResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "FindCredentials", "credential_type": req.Type}
	defer func() {
		duration := time.Since(start)
		c.statter.Counter(requestsMetric, tags, 1)
		c.statter.DistributionMs(timingMetric, tags, duration)
	}()

	for _, opt := range opts {
		ctx = opt(ctx)
	}

	response, err := c.twirpClient.FindCredentials(ctx, req)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	tags["result"] = response.Result.String()

	return response, nil
}

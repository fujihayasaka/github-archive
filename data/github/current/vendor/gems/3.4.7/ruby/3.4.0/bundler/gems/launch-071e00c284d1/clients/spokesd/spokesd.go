package spokesd

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/spokes-proto/gen/go/v1/blobs"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/objects"
	"github.com/github/spokes-proto/gen/go/v1/streaming"
	"github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/github/spokes-proto/gen/go/v1/types/selectors"
	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"
	"github.com/twitchtv/twirp"

	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/ahttp"
	"github.com/github/launch/utils/mathutils"
)

type Config struct {
	SpokesdURL   string
	BuildVersion string
	ServiceName  string
}

const (
	failFastBaseRetryInterval = 15 * time.Second
	failFastJitterRatio       = 0.50
	failFastMaxAttempts       = 5

	// Allow up to 20s (up from the ahttp default of 10s)
	// to accommodate CheckCommitReachability requests for large repositories.
	requestTimeout = 20 * time.Second

	// MaxTimeout must be set to match requestTimeout.
	// Otherwise, (for the common usage pattern of spokesd clients that are instantiated with an innerHTTPClient initialized via apphttp)
	// the stricter apphttp default of 10s will be enforced on the client side
	// and effectively abandon long-running requests that might otherwise succeed.
	// See https://github.com/github/git-systems/issues/3074 for more context.
	MaxTimeout = requestTimeout

	// RequestTimeoutHeader is the overall timeout in seconds for the request enforced by GitRPCd
	// This must be set to override the default timeout of 15 seconds
	// defined in https://github.com/github/gitrpcd/blob/b61794bdad27647aa32f5641b0d589c16d2ad5c5/internal/http/timeout/timeout.go#L14-L29
	RequestTimeoutHeader = "Request-Timeout"
)

type Client interface {
	GetBlobContents(ctx context.Context, req *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error)
	GetBlobContentsBatch(ctx context.Context, req *GetBlobContentsBatchRequest) (*GetBlobContentsBatchResponse, error)
	ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error)
	CheckCommitReachability(ctx context.Context, req *commits.CheckCommitReachabilityRequest) (*commits.CheckCommitReachabilityResponse, error)

	// ResolveObjectsByCommitShaAndPath returns a set of objectIDs for a list of paths and commit SHAs for a given repository
	ResolveObjectsByCommitShaAndPath(ctx context.Context, req *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error)

	// ResolveObjectsByRef returns the head commit SHAs for a list of refs for a given repository
	ResolveObjectsByRef(ctx context.Context, req *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error)
}

type client struct {
	blobsAPI   BlobsService
	objectsAPI ObjectsService
	commitsAPI CommitsService
	httpClient *ahttp.RetryClient
	userAgent  string
	spokesdURL string
}

func NewClient(cfg Config, innerHTTPClient *http.Client, statter statter.Statter, breaker *circuit.Breaker, clientOpts []twirp.ClientOption) (Client, error) {

	retryRand := mathutils.NewSynchronizedRandProviderFromClock()
	httpClient := ahttp.NewRetryClient(breaker, statter, innerHTTPClient, "spokesd-revised")
	httpClient.BackoffStrategy = ahttp.RandomizedExponentialBackoff(retryRand, failFastJitterRatio)
	httpClient.RetryInterval = failFastBaseRetryInterval
	httpClient.Attempts = failFastMaxAttempts

	userAgent := fmt.Sprintf("%s/%s", cfg.ServiceName, cfg.BuildVersion)
	return &client{
		blobsAPI:   blobs.NewBlobsAPIProtobufClient(cfg.SpokesdURL, httpClient, clientOpts...),
		objectsAPI: objects.NewObjectsAPIProtobufClient(cfg.SpokesdURL, httpClient, clientOpts...),
		commitsAPI: commits.NewCommitsAPIProtobufClient(cfg.SpokesdURL, httpClient, clientOpts...),
		httpClient: httpClient,
		spokesdURL: cfg.SpokesdURL,
		userAgent:  userAgent,
	}, nil
}

func NewMockTestClient(blobsClient BlobsService, objectsClient ObjectsService, commitsClient CommitsService, spokesdURL string) (Client, error) {

	testClient := ahttp.NewRetryClient(
		nil,
		statter.NullStatter(),
		http.DefaultClient,
		"spokes-test-client",
	)

	if commitsClient == nil {
		commitsClient = commits.NewCommitsAPIProtobufClient(spokesdURL, testClient)
	}

	return &client{
		blobsAPI:   blobsClient,
		objectsAPI: objectsClient,
		commitsAPI: commitsClient,
		httpClient: testClient,
		userAgent:  "spokes-test/v1.0",
		spokesdURL: spokesdURL,
	}, nil
}

func (c *client) GetBlobContents(ctx context.Context, req *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("GetBlobContentsRequest cannot be nil")
	}

	if req.RequestContext == nil {
		return nil, fmt.Errorf("GetBlobContentsRequest.RequestContext cannot be nil")
	}

	ctx, err := c.setHeaders(ctx, false)
	if err != nil {
		return nil, fmt.Errorf("setting user agent for blobs request: %w", err)
	}

	res, err := c.blobsAPI.GetBlobContents(ctx, req)
	if err != nil {
		return nil, err
	}

	return res, nil
}

// GetBlobContentsBatch accepts a collection of objectIds present in one repository
// and returns back the contents of the blobs.
func (c *client) GetBlobContentsBatch(ctx context.Context, req *GetBlobContentsBatchRequest) (*GetBlobContentsBatchResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("GetBlobContentsBatchRequest cannot be nil")
	}

	var spokesObjectIDs []*types.ObjectID
	for _, oid := range req.ObjectIDs {
		spokesObjectIDs = append(spokesObjectIDs, &types.ObjectID{
			Id: oid,
		})
	}

	batchBlobsRequest := streaming.NewBatchBlobsRequest(
		c.getSpokesdRequestContext(req.ActorID, req.QualityOfService),
		types.NewRepository(uint64(req.RepositoryID)),
		spokesObjectIDs,
	)

	httpReq, _ := streaming.NewBatchBlobsHTTPRequest(batchBlobsRequest, c.spokesdURL)
	resp, err := c.httpClient.DoWithRetries(httpReq)
	if err != nil {
		return nil, errors.Wrap(err, "spokes batch blob request failed")
	}
	defer resp.Body.Close()

	// The response is always a tar archive for this API.
	// The tar header comprises of metadata about the file and the name
	// of the header is the blobID.
	tar, err := streaming.GetBatchBlobsTarReader(resp)
	if err != nil {
		return nil, errors.Wrap(err, "getting tar reader")
	}

	blobContentsByID := make(BlobContentsByID)

	for {
		header, err := tar.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, errors.Wrap(err, "advancing to next entry in the tar archive")
		}

		content, err := io.ReadAll(tar)
		if err != nil {
			return nil, errors.Wrap(err, "reading entry contents")
		}

		blobContentsByID[header.Name] = Blob(content)
	}

	return &GetBlobContentsBatchResponse{
		RepositoryID:     req.RepositoryID,
		BlobContentsByID: blobContentsByID,
	}, nil
}

func (c *client) ResolveObject(ctx context.Context, req *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("ResolveObjectRequest cannot be nil")
	}

	if req.RequestContext == nil {
		return nil, fmt.Errorf("ResolveObjectRequest.RequestContext cannot be nil")
	}

	ctx, err := c.setHeaders(ctx, false)
	if err != nil {
		return nil, fmt.Errorf("setting user agent for objects request: %w", err)
	}

	res, err := c.objectsAPI.ResolveObject(ctx, req)
	if err != nil {
		return nil, err
	}

	return res, nil
}

func (c *client) ResolveObjectsByRef(ctx context.Context, req *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("ResolveObjectsRequest cannot be nil")
	}

	ctx, err := c.setHeaders(ctx, false)
	if err != nil {
		return nil, fmt.Errorf("setting user agent for resolve objects by ref request: %w", err)
	}
	var selector []*selectors.ObjectSelector

	for _, identifier := range req.ObjectIdentifierList {
		selector = append(selector,
			selectors.NewObjectSelectorByRevision(
				types.NewRevision([]byte(identifier.Ref)),
			),
		)
	}

	resolveObjectsRequest := objects.NewResolveObjectsRequest(
		c.getSpokesdRequestContext(req.ActorID, req.QualityOfService),
		types.NewRepository(uint64(req.RepositoryID)),
		selector...,
	)

	return c.resolveObjects(ctx, resolveObjectsRequest)
}

func (c *client) ResolveObjectsByCommitShaAndPath(ctx context.Context, req *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("ResolveObjectsRequest cannot be nil")
	}

	ctx, err := c.setHeaders(ctx, false)
	if err != nil {
		return nil, fmt.Errorf("setting user agent for resolve objects by commit sha and path request: %w", err)
	}

	var tree *types.Treeish
	var selector []*selectors.ObjectSelector

	for _, identifier := range req.ObjectIdentifierList {
		tree = types.NewTreeishWithObjectID(types.NewObjectID(identifier.SHA))
		selector = append(selector,
			selectors.NewObjectSelectorByTreeishAndPath(
				tree,
				types.NewPath([]byte(identifier.Path)),
			),
		)
	}

	resolveObjectsRequest := objects.NewResolveObjectsRequest(
		c.getSpokesdRequestContext(req.ActorID, req.QualityOfService),
		types.NewRepository(uint64(req.RepositoryID)),
		selector...,
	)

	return c.resolveObjects(ctx, resolveObjectsRequest)
}

func (c *client) CheckCommitReachability(ctx context.Context, req *commits.CheckCommitReachabilityRequest) (*commits.CheckCommitReachabilityResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("CheckCommitReachabilityRequest cannot be nil")
	}

	if req.RequestContext == nil {
		return nil, fmt.Errorf("CheckCommitReachabilityRequest.RequestContext cannot be nil")
	}

	ctx, err := c.setHeaders(ctx, true)
	if err != nil {
		return nil, fmt.Errorf("setting user agent for commits request: %w", err)
	}

	res, err := c.commitsAPI.CheckCommitReachability(ctx, req)
	if err != nil {
		return nil, err
	}

	return res, nil
}

func (c *client) resolveObjects(ctx context.Context, req *objects.ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	if req == nil {
		return nil, fmt.Errorf("ResolveObjectsRequest cannot be nil")
	}

	if req.RequestContext == nil {
		return nil, fmt.Errorf("ResolveObjectsRequest.RequestContext cannot be nil")
	}

	res, err := c.objectsAPI.ResolveObjects(ctx, req)
	if err != nil {
		return nil, err
	}

	return res, nil
}

func (c *client) setHeaders(ctx context.Context, includeRequestTimeout bool) (context.Context, error) {
	headers := http.Header{"User-Agent": []string{c.userAgent}}
	if includeRequestTimeout {
		headers.Set(RequestTimeoutHeader, fmt.Sprintf("%.0f", requestTimeout.Seconds()))
	}

	ctx, err := twirp.WithHTTPRequestHeaders(ctx, headers)
	if err != nil {
		return ctx, fmt.Errorf("setting headers: %w", err)
	}

	return ctx, nil
}

func (c *client) getSpokesdRequestContext(actorID int64, qos types.RequestContext_QualityOfService) *types.RequestContext {
	return types.NewRequestContext(qos, types.WithUserID(uint64(actorID)))
}

func LoadTLSConfig(spokesdCert, spokesdKey, spokesdChain string) (*tls.Config, error) {
	cert, err := tls.X509KeyPair([]byte(spokesdCert), []byte(spokesdKey))
	if err != nil {
		return nil, errors.Wrap(err, "parsing certificate and key")
	}

	caCertPool, err := x509.SystemCertPool()
	if err != nil {
		return nil, err
	}

	ok := caCertPool.AppendCertsFromPEM([]byte(spokesdChain))
	if !ok {
		return nil, errors.New("failed to append certificates")
	}

	return &tls.Config{
		Certificates: []tls.Certificate{cert},
		RootCAs:      caCertPool,
	}, nil
}

// No-op spokesD client
type NullSpokesClient struct{}

func (c NullSpokesClient) GetBlobContents(_ context.Context, _ *blobs.GetBlobContentsRequest) (*blobs.GetBlobContentsResponse, error) {
	return &blobs.GetBlobContentsResponse{}, nil
}

func (c NullSpokesClient) GetBlobContentsBatch(_ context.Context, _ *GetBlobContentsBatchRequest) (*GetBlobContentsBatchResponse, error) {
	return nil, nil
}

func (c NullSpokesClient) ResolveObject(_ context.Context, _ *objects.ResolveObjectRequest) (*objects.ResolveObjectResponse, error) {
	return &objects.ResolveObjectResponse{}, nil
}

func (c NullSpokesClient) ResolveObjectsByRefAndPath(_ context.Context, _ *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return &objects.ResolveObjectsResponse{}, nil
}

func (c NullSpokesClient) ResolveObjectsByRef(_ context.Context, _ *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return &objects.ResolveObjectsResponse{}, nil
}

func (c NullSpokesClient) ResolveObjectsByCommitShaAndPath(_ context.Context, _ *ResolveObjectsRequest) (*objects.ResolveObjectsResponse, error) {
	return &objects.ResolveObjectsResponse{}, nil
}

func (c NullSpokesClient) CheckCommitReachability(_ context.Context, _ *commits.CheckCommitReachabilityRequest) (*commits.CheckCommitReachabilityResponse, error) {
	return &commits.CheckCommitReachabilityResponse{}, nil
}

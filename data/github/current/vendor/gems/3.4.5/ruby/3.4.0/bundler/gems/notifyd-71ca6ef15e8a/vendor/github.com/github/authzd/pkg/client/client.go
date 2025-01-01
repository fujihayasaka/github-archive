package client

import (
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/github/authzd/pkg/capevaluator"
	"github.com/github/authzd/pkg/enumerator"
	"github.com/github/authzd/pkg/proto"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-twirp/v2/client/requestid"
	"github.com/twitchtv/twirp"
)

var ErrEmptyBatch = errors.New("batch_request is empty")

// Client is a unified interface for authzd services
type Client interface {
	proto.Authorizer
	enumerator.Enumerator
	capevaluator.CapEvaluator
}

// client is a facade around the twirp interfaces. This provides access to both interfaces with a single service object
type client struct {
	authorizer   proto.Authorizer
	enumerator   enumerator.Enumerator
	capevaluator capevaluator.CapEvaluator
}

func (c *client) ForActor(ctx context.Context, req *enumerator.ForActorRequest) (*enumerator.ForActorResponse, error) {
	return c.enumerator.ForActor(ctx, req)
}

func (c *client) ForSubject(ctx context.Context, req *enumerator.ForSubjectRequest) (*enumerator.ForSubjectResponse, error) {
	return c.enumerator.ForSubject(ctx, req)
}

func (c *client) Authorize(ctx context.Context, req *proto.Request) (*proto.Decision, error) {
	return c.authorizer.Authorize(ctx, req)
}

func (c *client) BatchAuthorize(ctx context.Context, req *proto.BatchRequest) (*proto.BatchDecision, error) {
	if len(req.GetRequests()) == 0 {
		return nil, ErrEmptyBatch
	}
	return c.authorizer.BatchAuthorize(ctx, req)
}

func (c *client) EvaluatePoliciesForSingleResource(ctx context.Context, req *capevaluator.SingleResourceRequest) (*capevaluator.SingleResourceResponse, error) {
	return c.capevaluator.EvaluatePoliciesForSingleResource(ctx, req)
}

func newClient(a proto.Authorizer, e enumerator.Enumerator, c capevaluator.CapEvaluator) Client {
	return &client{
		authorizer:   a,
		enumerator:   e,
		capevaluator: c,
	}
}

func New(addr string, opts ...Option) (Client, error) {
	clientOpts := &options{
		HTTPClient:     http.DefaultClient,
		HTTPMiddleware: []HTTPMiddleware{},
		Middleware:     []Middleware{},
		ClientOpts:     []twirp.ClientOption{},
	}
	for _, opt := range opts {
		err := opt(clientOpts)
		if err != nil {
			return nil, err
		}
	}

	httpClient := clientOpts.HTTPClient
	var err error

	// Apply any configured HTTP Middleware to the client.
	for _, opt := range clientOpts.HTTPMiddleware {
		httpClient, err = opt(httpClient)
		if err != nil {
			return nil, err
		}
	}

	enumeratorClient := enumerator.NewEnumeratorProtobufClient(addr, httpClient, clientOpts.ClientOpts...)
	authorizerClient := proto.NewAuthorizerProtobufClient(addr, httpClient, clientOpts.ClientOpts...)
	capEvaluatorClient := capevaluator.NewCapEvaluatorProtobufClient(addr, httpClient, clientOpts.ClientOpts...)

	client := newClient(authorizerClient, enumeratorClient, capEvaluatorClient)

	for _, opt := range clientOpts.Middleware {
		client, err = opt(client)
		if err != nil {
			return nil, err
		}
	}

	return client, nil
}

// HTTPClient enables the creation of middlewares around *(net/http).Client.
type HTTPClient interface {
	Do(req *http.Request) (*http.Response, error)
}

type httpClientFunc func(req *http.Request) (*http.Response, error)

func (h httpClientFunc) Do(req *http.Request) (*http.Response, error) {
	return h(req)
}

// options contains all the options we need to construct the API client.
type options struct {
	HTTPClient     HTTPClient
	HTTPMiddleware []HTTPMiddleware
	Middleware     []Middleware
	ClientOpts     []twirp.ClientOption
}

// Option is a functional option type to control construction of the Authorizer or Enumerator client.
type Option func(*options) error

// WithHTTPClient allows callers to override the default HTTP client.
func WithHTTPClient(client HTTPClient) Option {
	return func(c *options) error {
		c.HTTPClient = client
		return nil
	}
}

// WithTwirpClientOptions allows callers to provide Twirp Client options.
func WithTwirpClientOptions(opts ...twirp.ClientOption) Option {
	return func(c *options) error {
		c.ClientOpts = opts
		return nil
	}
}

// WithRequestHeader sets a HTTP request header to a specified value
func WithRequestHeader(header string, headerValue string) Option {
	return withHTTPMiddleware(
		func(c HTTPClient) (HTTPClient, error) {
			return httpClientFunc(func(r *http.Request) (*http.Response, error) {
				r.Header.Set(header, headerValue)
				return c.Do(r)
			}), nil
		},
	)
}

// WithUserAgent forwards a specific string as part of the http request User-Agent header, used commonly to identify
// clients at GitHub
func WithUserAgent(id string) Option {
	return WithRequestHeader("User-Agent", id)
}

// WithHMACSignature sets the Request-HMAC header with a token generated from the provided secret
func WithHMACSignature(secret string) Option {
	return withHTTPMiddleware(
		func(c HTTPClient) (HTTPClient, error) {
			return httpClientFunc(func(r *http.Request) (*http.Response, error) {
				hmacToken := hmac.NewRequestHMAC(secret).String()
				r.Header.Set(headers.RequestHMAC, hmacToken)
				return c.Do(r)
			}), nil
		},
	)
}

// WithRequestIDForwarder enables the forwarding of GitHub's request_id used for tracing a user request to
// github.com through each of the different services in the request lifecycle.
func WithRequestIDForwarder() Option {
	return withHTTPMiddleware(
		func(c HTTPClient) (HTTPClient, error) {
			return requestid.NewForwarder(c), nil
		},
	)
}

// WithBatchSlicing enables slicing of BatchAuthorize requests, by issuing smaller batch requests with a maximum
// size defined by the "sliceSize" argument. This helps spread the load across the service fleet.
// It's recommended to do batch slicing when you expect slices to be larger than 100 elements.
//
// maxConcurrency defines the maximum number of concurrent requests for each one of the slices. It is currently a no-op but
// will be relevant once splitting batches into concurrently executed slices is implemented.
func WithBatchSlicing(sliceSize int, maxConcurrency int) Option {
	return WithMiddleware(func(client Client) (Client, error) {
		return newBatchSlicingMiddleware(sliceSize, maxConcurrency, client)
	})
}

func newBatchSlicingMiddleware(sliceSize int, maxConcurrency int, delegate Client) (Client, error) {
	if sliceSize <= 0 {
		return nil, errors.New("sliceSize must be greater than 0")
	}
	return &slicingClient{
		sliceSize:      sliceSize,
		maxConcurrency: maxConcurrency,
		delegate:       delegate,
	}, nil
}

type slicingClient struct {
	sliceSize      int
	maxConcurrency int
	delegate       Client
}

func (m *slicingClient) Authorize(ctx context.Context, request *proto.Request) (*proto.Decision, error) {
	return m.delegate.Authorize(ctx, request)
}

func (m *slicingClient) BatchAuthorize(ctx context.Context, request *proto.BatchRequest) (*proto.BatchDecision, error) {
	pendingRequestLen := len(request.GetRequests())

	if pendingRequestLen == 0 {
		return nil, ErrEmptyBatch
	}
	if pendingRequestLen <= m.sliceSize {
		return m.delegate.BatchAuthorize(ctx, request)
	}

	batchDecisions := make([]*proto.Decision, pendingRequestLen)
	for index := 0; index <= pendingRequestLen; index += m.sliceSize {
		indexPoint := index + m.sliceSize
		if indexPoint > pendingRequestLen {
			indexPoint = pendingRequestLen
		}

		var batch proto.BatchRequest

		batch.Requests = request.GetRequests()[index:indexPoint]
		batchResponse, err := m.delegate.BatchAuthorize(ctx, &batch)
		if err != nil {
			return nil, fmt.Errorf("split Batch Error: %w", err)
		}
		n := copy(batchDecisions[index:indexPoint], batchResponse.GetDecisions())
		if n != indexPoint-index {
			return nil, errors.New("split Batch Error: incorrect number of elements copied")
		}
	}
	return &proto.BatchDecision{Decisions: batchDecisions}, nil
}

func (m *slicingClient) ForActor(ctx context.Context, request *enumerator.ForActorRequest) (*enumerator.ForActorResponse, error) {
	return m.delegate.ForActor(ctx, request)
}

func (m *slicingClient) ForSubject(ctx context.Context, request *enumerator.ForSubjectRequest) (*enumerator.ForSubjectResponse, error) {
	return m.delegate.ForSubject(ctx, request)
}

func (m *slicingClient) EvaluatePoliciesForSingleResource(ctx context.Context, request *capevaluator.SingleResourceRequest) (*capevaluator.SingleResourceResponse, error) {
	return m.delegate.EvaluatePoliciesForSingleResource(ctx, request)
}

// withHTTPMiddleware allows callers to wrap HTTPClient with their own middleware. Order in
// which the middlewares are added will be reflected in the final middleware chain, FIFO style.
func withHTTPMiddleware(h HTTPMiddleware) Option {
	return func(c *options) error {
		c.HTTPMiddleware = append(c.HTTPMiddleware, h)
		return nil
	}
}

func WithMiddleware(a Middleware) Option {
	return func(c *options) error {
		c.Middleware = append(c.Middleware, a)
		return nil
	}
}

// HTTPMiddleware is used to wrap the HTTPClient that is used to perform the RPC calls to the
// server.
type HTTPMiddleware func(HTTPClient) (HTTPClient, error)

// Middleware is used to wrap the Client interface
type Middleware func(client Client) (Client, error)

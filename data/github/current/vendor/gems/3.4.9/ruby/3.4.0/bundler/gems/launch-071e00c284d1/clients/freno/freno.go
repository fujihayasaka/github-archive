package freno

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	"github.com/pkg/errors"
	circuit "github.com/rubyist/circuitbreaker"
	"go.opentelemetry.io/otel/attribute"
	"golang.org/x/sync/singleflight"

	"github.com/github/launch/observability/tracing"
)

type Client interface {
	Check(ctx context.Context, cluster string) (*CheckResponse, error)
	CanWriteToClusters(ctx context.Context, clusters ...string) (map[string]bool, error)
}

type clientOpts struct {
	timeout    time.Duration
	httpClient *http.Client
	breaker    *circuit.Breaker
}

type ClientOpt func(*clientOpts) error

func UseTimeout(timeout time.Duration) ClientOpt {
	return func(opts *clientOpts) error {
		opts.timeout = timeout
		return nil
	}
}

type client struct {
	cfg     *clientOpts
	baseURL *url.URL
	sfg     *singleflight.Group
	hooks   *ClientHooks

	// overrideCluster overrides the individual cluster requested by the callers of `Check`.
	// In Proxima environments, there is only a single cluster
	overrideCluster string
}

func NewClient(address, overrideCluster string, hooks *ClientHooks, httpClient *http.Client, cb *circuit.Breaker, opts ...ClientOpt) (Client, error) {
	u, err := url.Parse(address)
	if err != nil {
		return nil, errors.Wrap(err, "invalid address")
	}

	if cb == nil {
		return nil, errors.New("circuit breaker is required")
	}

	defaultOpts := &clientOpts{
		timeout:    2 * time.Second,
		httpClient: httpClient,
		breaker:    cb,
	}
	for _, opt := range opts {
		if err := opt(defaultOpts); err != nil {
			return nil, err
		}
	}

	hooks.ensureDefaults()
	return &client{
		cfg:             defaultOpts,
		baseURL:         u,
		sfg:             new(singleflight.Group),
		hooks:           hooks,
		overrideCluster: overrideCluster,
	}, nil
}

func (cl *client) do(ctx context.Context, method, path string, out json.Unmarshaler) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	ctx, cancel := context.WithTimeout(ctx, cl.cfg.timeout)
	defer cancel()

	u, err := cl.baseURL.Parse(path)
	if err != nil {
		return errors.Wrap(err, "preparing URL for HTTP request")
	}

	flightKey := method + "/" + u.String()
	wait := cl.sfg.DoChan(flightKey, func() (any, error) {
		return cl.doSingleFlight(ctx, method, u.String())
	})

	var res singleflight.Result
	select {
	case <-ctx.Done():
		return ctx.Err()
	case res = <-wait:
	}
	span.SetAttributes(attribute.Bool("gh.launch.sf.shared", res.Shared))
	if res.Err != nil {
		return tracing.RecordError(span, res.Err)
	}
	if res.Val == nil {
		return nil
	}
	if raw, ok := res.Val.([]byte); ok && len(raw) > 0 {
		if err := out.UnmarshalJSON(raw); err != nil {
			return tracing.RecordError(span, errors.Wrap(err, "decoding JSON response"))
		}
	}
	return nil
}

func (cl *client) doSingleFlight(ctx context.Context, method, url string) ([]byte, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	if !cl.cfg.breaker.Ready() {
		return nil, circuit.ErrBreakerOpen
	}
	success := false
	defer func() {
		if !success {
			cl.cfg.breaker.Fail()
		} else {
			cl.cfg.breaker.Success()
		}
	}()
	req, err := http.NewRequestWithContext(ctx, method, url, nil)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "creating request"))
	}
	res, err := cl.cfg.httpClient.Do(req)
	if err != nil {
		return nil, tracing.RecordError(span, errors.Wrap(err, "performing HTTP request"))
	}
	if res == nil {
		return nil, tracing.RecordError(span, errors.New("No response"))
	}
	if res.Body == nil {
		// this may need to be reworked if HEAD request support is added
		return nil, tracing.RecordError(span, errors.New("No response body"))
	}
	defer res.Body.Close()

	if res.StatusCode >= 200 && res.StatusCode < 500 {
		success = true
		body, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
		if err != nil {
			return nil, tracing.RecordError(span, errors.Wrap(err, "reading body"))
		}
		return body, nil
	}
	return nil, tracing.RecordError(span, errors.Errorf("Unexpected freno response code %d", res.StatusCode))
}

var _ json.Unmarshaler = (*CheckResponse)(nil)

type CheckResponse struct {
	CanWrite       bool
	StatusCode     int
	ReplicationLag time.Duration
	Threshold      time.Duration
	Message        string
}

func (res *CheckResponse) UnmarshalJSON(p []byte) error {
	var v struct {
		StatusCode int     `json:"StatusCode"`
		Value      float64 `json:"Value"`
		Threshold  float64 `json:"Threshold"`
		Message    string  `json:"Message"`
	}
	if err := json.Unmarshal(p, &v); err != nil {
		return err
	}
	res.CanWrite = v.StatusCode == http.StatusOK
	res.StatusCode = v.StatusCode

	res.ReplicationLag = time.Duration(
		// value is a float in seconds with 6 significant digits, so
		// we scale it up by 6 digits before casting it to an integer
		v.Value*1e6,
	) * time.Microsecond

	res.Threshold = time.Duration(
		v.Threshold*1e6,
	) * time.Microsecond

	res.Message = v.Message
	return nil
}

func (cl *client) Check(ctx context.Context, cluster string) (*CheckResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	dbCluster := cluster
	if cl.overrideCluster != "" {
		dbCluster = cl.overrideCluster
	}

	path := fmt.Sprintf("check/%s/%s/%s", AppName, DBType, dbCluster)

	res := new(CheckResponse)
	hc := cl.hooks.OnBeginRPC(ctx, "freno", "check", AppName, DBType, dbCluster)
	defer func() { cl.hooks.OnEndRPC(ctx, hc, res) }()

	err := cl.do(ctx, http.MethodGet, path, res)

	if err != nil {
		return nil, errors.Wrap(err, "performing HTTP request to Check API")
	}

	return res, nil
}

func (cl *client) CanWriteToClusters(ctx context.Context, clusters ...string) (map[string]bool, error) {
	if cl.overrideCluster != "" {
		clusters = []string{cl.overrideCluster}
	}

	results := make(map[string]bool)
	for _, cluster := range clusters {
		res, err := cl.Check(ctx, cluster)
		if err != nil {
			return nil, errors.Wrap(err, "checking cluster")
		}
		results[cluster] = res.CanWrite
	}
	return results, nil
}

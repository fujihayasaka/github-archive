// Package lag contains a way to get the current replication lag from Freno.
package lag

import (
	"context"
	"encoding/json"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/turboghas/proto"
	"github.com/pkg/errors"
)

type Client interface {
	Value(ctx context.Context, cluster string) (time.Duration, error)
}

type nullClient struct{}

func (nullClient) Value(_ context.Context, _ string) (time.Duration, error) {
	return 0, nil
}

var NullClient Client = nullClient{}

// FrenoClient can connect to freno and fetch the current replication lag.
func FrenoClient(addr string, client proto.HTTPClient) Client {
	return &frenoClient{
		addr:   addr,
		client: client,
	}
}

type frenoClient struct {
	addr   string
	client proto.HTTPClient
}

var ErrUnknownCluster = errors.New("unknown cluster")

// Value returns the current replication lag for cluster.
func (c *frenoClient) Value(ctx context.Context, cluster string) (time.Duration, error) {
	var v time.Duration

	dest := &url.URL{
		Scheme: "http",
		Host:   c.addr,
		Path:   strings.Join([]string{"check", "github", "mysql", cluster}, "/"),
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, dest.String(), http.NoBody)
	if err != nil {
		return v, err
	}

	resp, err := c.client.Do(req)
	if err != nil {
		return v, err
	}

	var frenoResponse struct {
		Value      float64
		StatusCode int
	}

	decodeErr := json.NewDecoder(resp.Body).Decode(&frenoResponse)

	if closeErr := resp.Body.Close(); closeErr != nil {
		return v, errors.Wrap(closeErr, "failed to close freno response body")
	}

	if decodeErr != nil {
		return v, errors.Wrap(decodeErr, "could not decode freno response")
	}

	v = time.Duration(frenoResponse.Value * 1_000_000_000)

	if frenoResponse.StatusCode != http.StatusOK {
		if frenoResponse.StatusCode == http.StatusNotFound {
			return v, ErrUnknownCluster
		}
		return v, errors.Errorf("freno returned status %d", frenoResponse.StatusCode)
	}

	return v, nil
}

type cacheClient struct {
	cache  map[string]cacheValue
	next   Client
	minTTL time.Duration
}

type cacheValue struct {
	until time.Time
	value time.Duration
}

// Cache returns a client that will cache the result of Value for minTTL or the maximum latency, whichever is higher
func Cache(next Client, minTTL time.Duration) Client {
	return &cacheClient{
		cache:  map[string]cacheValue{},
		next:   next,
		minTTL: minTTL,
	}
}

// Value returns the current replication lag for cluster using a cached value if it is not stale
func (c *cacheClient) Value(ctx context.Context, cluster string) (time.Duration, error) {
	if v, ok := c.cache[cluster]; ok && time.Until(v.until) > 0 {
		return v.value, nil
	}
	lag, err := c.next.Value(ctx, cluster)
	if err == nil {
		c.cache[cluster] = cacheValue{
			until: time.Now().Add(max(lag, c.minTTL)),
			value: lag,
		}
	}

	return lag, err
}

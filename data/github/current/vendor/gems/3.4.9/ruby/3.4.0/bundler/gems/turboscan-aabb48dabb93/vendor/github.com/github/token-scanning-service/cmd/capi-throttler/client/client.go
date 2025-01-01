package client

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/hashicorp/go-retryablehttp"

	"github.com/github/token-scanning-service/ts/httputil"
	"github.com/github/token-scanning-service/ts/utils"
)

type CapiThrottler interface {
	GetDelay(ctx context.Context, model string, tokens int) (int64, error)
	Workload() string
}

var _ CapiThrottler = &Client{}

type Client struct {
	baseURL    string
	httpClient *httputil.Client
	workload   string
}

var _ CapiThrottler = &NoopThrottlerClient{}

type NoopThrottlerClient struct {
	baseURL    string
	httpClient *httputil.Client
	workload   string
}

func NewCapiThrottler(logger log.Logger, baseURL string, workload string) (*Client, error) {
	client, err := httputil.NewHTTPClient(
		httputil.WithLogger(logger),
		httputil.WithAttempts(2),
		httputil.WithInitialBackoff(1*time.Second),
		httputil.WithMaxBackoff(2*time.Second),
		httputil.WithBackoffStrategy(httputil.LinearJitter),
		httputil.WithHTTPClient(&http.Client{Timeout: 3 * time.Second}),
		httputil.WithRetryPolicy(func(ctx context.Context, resp *http.Response, err error) (bool, error) {
			retry, policyErr := retryablehttp.DefaultRetryPolicy(ctx, resp, err)
			if retry || policyErr != nil {
				return retry, policyErr
			}

			// DefaultRetryPolicy handles everything we need except retrying on all non-2xx responses
			retry = err == nil && (resp.StatusCode < 200 || resp.StatusCode > 299)
			return retry, nil
		}),
		httputil.WithErrorHandler(func(resp *http.Response, err error, attempt int) (*http.Response, error) {
			// we need a stub error handler for the inner exception to be logged (need to track down why)
			return resp, err
		}),
	)
	if err != nil {
		return nil, err
	}
	return &Client{
		baseURL:    baseURL,
		workload:   workload,
		httpClient: client,
	}, nil
}

type CheckResponse struct {
	// Delay in milliseconds
	Delay int64 `json:"delay"`
}

func (c *Client) Workload() string {
	return c.workload
}

// GetDelay returns a delay in seconds
func (c *Client) GetDelay(ctx context.Context, model string, tokens int) (int64, error) {
	reqURL, err := url.Parse(c.baseURL)
	if err != nil {
		return -1, err
	}
	reqURL = reqURL.JoinPath("check", model, c.workload)

	values := reqURL.Query()
	values.Set("tokens", strconv.Itoa(tokens))
	reqURL.RawQuery = values.Encode()

	req, err := http.NewRequestWithContext(ctx, "GET", reqURL.String(), nil)
	if err != nil {
		return -1, err
	}

	req.Header.Add("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return -1, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return -1, fmt.Errorf("unexpected status code: %d", resp.StatusCode)
	}

	checkResponse := CheckResponse{}
	err = json.NewDecoder(resp.Body).Decode(&checkResponse)
	if err != nil {
		return -1, err
	}

	return checkResponse.Delay, nil
}

func NewNoopCapiThrottler(ctx context.Context, baseURL string, workload string) (*NoopThrottlerClient, error) {
	logger := utils.LoggerFromContext(ctx)
	if logger == nil {
		logger = log.NewNullLogger()
	}

	client, err := httputil.NewHTTPClient(
		httputil.WithLogger(logger),
		httputil.WithAttempts(2),
		httputil.WithInitialBackoff(0*time.Second),
		// httputil.WithMaxBackoff(2*time.Second),
		// httputil.WithBackoffStrategy(httputil.LinearJitter),
		httputil.WithHTTPClient(&http.Client{Timeout: 3 * time.Second}),
		httputil.WithRetryPolicy(func(ctx context.Context, resp *http.Response, err error) (bool, error) {
			retry, policyErr := retryablehttp.DefaultRetryPolicy(ctx, resp, err)
			if retry || policyErr != nil {
				return retry, policyErr
			}

			// DefaultRetryPolicy handles everything we need except retrying on all non-2xx responses
			retry = err == nil && (resp.StatusCode < 200 || resp.StatusCode > 299)
			return retry, nil
		}),
		httputil.WithErrorHandler(func(resp *http.Response, err error, attempt int) (*http.Response, error) {
			// we need a stub error handler for the inner exception to be logged (need to track down why)
			return resp, err
		}),
	)
	if err != nil {
		return nil, err
	}
	return &NoopThrottlerClient{
		baseURL:    baseURL,
		workload:   workload,
		httpClient: client,
	}, nil
}

// GetDelay implements CapiThrottler.
func (n *NoopThrottlerClient) GetDelay(ctx context.Context, model string, tokens int) (int64, error) {
	return 0, nil
}

// Workload implements CapiThrottler.
func (n *NoopThrottlerClient) Workload() string {
	return n.workload
}

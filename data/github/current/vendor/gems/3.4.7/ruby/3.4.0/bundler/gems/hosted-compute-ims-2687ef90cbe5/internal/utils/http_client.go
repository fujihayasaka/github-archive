package utils

import (
	"bytes"
	"context"
	"io"
	"math"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/telemetry/statter"
)

const (
	defaultAttempts = uint(3)
)

type IHttpClient interface {
	Do(*http.Request) (*http.Response, error)
}

type RetryableHttpClientWithLogging struct {
	clientName    string
	attemptsCount uint
	client        IHttpClient
	enableStats   bool
}

func NewRetryableHttpClientWithLogging(clientName string) *RetryableHttpClientWithLogging {
	return &RetryableHttpClientWithLogging{
		clientName:    clientName,
		attemptsCount: defaultAttempts,
		client:        &http.Client{},
		enableStats:   true,
	}
}

func (c *RetryableHttpClientWithLogging) WithTelemetrySettings(enableStats bool) *RetryableHttpClientWithLogging {
	c.enableStats = enableStats

	return c
}

func (c *RetryableHttpClientWithLogging) WithRetrySettings(attemptsCount uint) *RetryableHttpClientWithLogging {
	c.attemptsCount = attemptsCount

	return c
}

func (c *RetryableHttpClientWithLogging) WithInternalHttpClient(httpClient IHttpClient) *RetryableHttpClientWithLogging {
	c.client = httpClient

	return c
}

func (c *RetryableHttpClientWithLogging) Do(req *http.Request) (*http.Response, error) {
	var (
		ctx = req.Context()
		res *http.Response
		err error
		buf *bytes.Reader
	)

	if req.Body != nil {
		body, err := io.ReadAll(req.Body)
		if err != nil {
			return nil, err
		}

		buf = bytes.NewReader(body)
		req.Body = io.NopCloser(buf)
	}

	for i := uint(0); i < c.attemptsCount; i++ {
		if res != nil {
			res.Body.Close()
		}

		requestStartTime := time.Now()
		res, err = c.client.Do(req)

		c.logOutboundStats(req, res, time.Since(requestStartTime), i)

		select {
		case <-ctx.Done():
			return nil, context.Canceled
		default:
		}

		if err != nil || res.StatusCode >= 500 {
			if req.Body != nil {
				if _, err := buf.Seek(0, 0); err != nil {
					return res, err
				}
				req.Body = io.NopCloser(buf)
			}

			if i+1 < c.attemptsCount {
				time.Sleep(c.getIntervalBeforeNextAttempt(i + 1))
			}

			continue
		}

		return res, err
	}

	return res, err
}

func (c *RetryableHttpClientWithLogging) getIntervalBeforeNextAttempt(attemptIndex uint) time.Duration {
	return time.Duration(math.Pow(2, float64(attemptIndex))) * time.Second
}

func (c *RetryableHttpClientWithLogging) logOutboundStats(req *http.Request, res *http.Response, requestDuration time.Duration, attemptIndex uint) {
	if !c.enableStats {
		return
	}

	statusCode := -1
	if res != nil {
		statusCode = res.StatusCode
	}

	ctx := req.Context()
	fields := []kvp.Field{
		kvp.String("client_name", c.clientName),
		kvp.String("method", req.Method),
		kvp.String("url", req.URL.String()),
		kvp.Int("status_code", statusCode),
		kvp.Uint("attempt", attemptIndex+1),
	}
	statter.Increment(ctx, "http.outbound.request", fields...)
	statter.DistributionMs(ctx, "http.outbound.request_duration", requestDuration, fields...)

	logger.Info(ctx, "outbound http request", append(fields, kvp.Duration("duration", requestDuration))...)
}

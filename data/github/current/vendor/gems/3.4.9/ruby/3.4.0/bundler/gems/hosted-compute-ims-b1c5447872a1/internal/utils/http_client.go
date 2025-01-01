package utils

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
	"github.com/github/hosted-compute-core/telemetry"
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
	logger        *telemetry.ReportingLogger
	enableStats   bool
}

func NewRetryableHttpClientWithLogging(clientName string, logger *telemetry.ReportingLogger) *RetryableHttpClientWithLogging {
	return &RetryableHttpClientWithLogging{
		clientName:    clientName,
		attemptsCount: defaultAttempts,
		client:        &http.Client{},
		logger:        logger,
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
	if c.logger == nil || !c.enableStats {
		return
	}

	statusCode := -1
	if res != nil {
		statusCode = res.StatusCode
	}

	tags := stats.Tags{
		"method":      req.Method,
		"url":         req.URL.String(),
		"status_code": fmt.Sprint(statusCode),
		"attempt":     fmt.Sprint(attemptIndex + 1),
		"client_name": c.clientName,
	}
	c.logger.Statter.Counter("http.outbound.request", tags, 1)
	c.logger.Statter.DistributionMs("http.outbound.request_duration", tags, requestDuration)

	c.logger.Info("outbound http request",
		kvp.String("method", req.Method),
		kvp.String("url", req.URL.String()),
		kvp.Int("status_code", statusCode),
		kvp.Uint("attempt", attemptIndex+1),
		kvp.Duration("duration", requestDuration),
		kvp.String("client_name", c.clientName),
	)
}

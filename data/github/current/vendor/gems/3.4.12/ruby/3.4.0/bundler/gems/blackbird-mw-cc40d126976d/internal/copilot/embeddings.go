package copilot

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/github/blackbird-mw/internal/retry"

	"github.com/cenkalti/backoff/v4"
	"github.com/github/go-auth/hmac"
	"github.com/github/go-http/middleware/headers"
	"github.com/github/go-http/middleware/requestid"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	"github.com/pkg/errors"
)

// In addition to per-user and overall rate limits, the Copilot API has a front-door rate limiter that allows
// 30 requests every 3 seconds per user. Rate limit errors are retried but eventually returned to the callers
// if the retries fail.
var ErrResourceExhausted = errors.New("failed to compute embeddings due to resource exhaustion")

//go:generate counterfeiter . Client
type Client interface {
	GetEmbedding(ctx context.Context, prompt string, userID uint32, model string, dimensions int) ([]float32, error)
}

func NewClient(baseURL string, hmacSecret string, httpClient *http.Client) Client {
	return &copilotClient{
		strings.TrimSuffix(baseURL, "/"),
		hmacSecret,
		httpClient,
	}
}

type copilotClient struct {
	baseURL    string
	hmac       string
	httpClient *http.Client
}
type embeddingResponse struct {
	Model  string           `json:"model"`
	Object string           `json:"object"`
	Data   []*embeddingElem `json:"data"`
}

type embeddingElem struct {
	Embedding []float32 `json:"embedding"`
	Index     uint32    `json:"index"`
	Object    string    `json:"object"`
}

func (c *copilotClient) GetEmbedding(ctx context.Context, prompt string, userID uint32, model string, dimensions int) ([]float32, error) {
	if len(prompt) == 0 {
		return nil, errors.New("empty prompt")
	}

	// Note: This model must match the index's model.
	// See: https://github.com/github/blackbird/blob/d6b8a7171b755a6dd6835679a1380b4d981c8beb/crates/copilot-api/src/lib.rs#L22
	reqPayload, err := json.Marshal(&struct {
		Model      string   `json:"model"`
		Input      []string `json:"input"`
		Dimensions int      `json:"dimensions,omitempty"`
	}{

		Model:      model,
		Input:      []string{prompt},
		Dimensions: dimensions,
	})

	if err != nil {
		return nil, errors.Wrap(err, "copilot request marshaling failed")
	}

	url := fmt.Sprintf("%s/embeddings", c.baseURL)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(reqPayload))
	if err != nil {
		return nil, errors.Wrap(err, "failed to create http request")
	}

	const CopilotIntegrationID = "blackbird-query"
	requestid.Forward(req)
	req.Header.Add(headers.RequestHMAC, hmac.NewRequestHMAC(c.hmac).String())
	req.Header.Add("Copilot-Integration-Id", CopilotIntegrationID)
	req.Header.Add("X-GitHub-User", strconv.FormatUint(uint64(userID), 10))

	var embedding []float32
	operation := func() error {
		start := time.Now()
		resp, err := c.httpClient.Do(req)
		if err != nil {
			return err
		}

		defer func() {
			statting.DistributionMs(ctx, "copilot.get_embedding.duration", time.Since(start), stats.Tags{"http_status": resp.Status})
			resp.Body.Close()
		}()

		err = retry.CheckHTTPResponse(resp, nil)
		if err != nil {
			if resp.StatusCode == http.StatusTooManyRequests {
				logging.Error(ctx, "hit copilot rate limit", kvp.Err(err))
				return ErrResourceExhausted
			}
			return err
		}

		respBytes, err := io.ReadAll(resp.Body)
		if err != nil {
			return backoff.Permanent(errors.Wrap(err, "could not read copilot API response"))
		}

		var eResp embeddingResponse
		err = json.Unmarshal(respBytes, &eResp)
		if err != nil {
			return backoff.Permanent(errors.Wrap(err, "could not unmarshal embedding response payload"))
		}
		if len(eResp.Data) != 1 {
			return backoff.Permanent(errors.Errorf("expected exactly 1 embedding got %d", len(eResp.Data)))
		}

		embedding = eResp.Data[0].Embedding
		// TODO: remove this truncation when the dimension parameter is supported in CAPI
		if len(embedding) > dimensions {
			embedding = embedding[0:dimensions]

			// Normalize the embeddings after truncation
			var norm float32 = 0.0
			for _, x := range embedding {
				norm += x * x
			}
			for i := range embedding {
				embedding[i] = embedding[i] / float32(math.Sqrt(float64(norm)))
			}
		}

		if len(embedding) != dimensions {
			return backoff.Permanent(errors.Errorf("unexpected embedding size received, model:%s, expected:%d, received:%d", model, dimensions, len(embedding)))
		}

		return nil
	}

	const maxRetries = 2
	err = backoff.Retry(operation, retry.LowLatencyBackoff(ctx, maxRetries))
	if err != nil {
		return nil, err
	}
	if embedding == nil {
		return nil, errors.New("no embedding set and no retry error!")
	}

	return embedding, nil
}

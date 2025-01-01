package vssf_runner

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/hosted-compute-core/telemetry"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_token"
	"github.com/golang-jwt/jwt"
)

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_vssf_runner/mock_runner.go -package mocks_runner
type Client interface {
	KnownRunnerUrls() []string
	GetImageUsage(ctx context.Context, runnerUrl string, image_id uint64) (*ImageUsage, error)
}

type runnerClient struct {
	knownRunnerUrls []string
	httpClient      *utils.RetryableHttpClientWithLogging
	tokenClient     vssf_token.Client
	logger          *telemetry.ReportingLogger
	jwtToken        string
}

func NewClient(cfg *Config, tokenCfg *vssf_token.Config, logger *telemetry.ReportingLogger) (Client, error) {
	// Create new runner client
	tokenClient, err := vssf_token.NewClient(tokenCfg, logger)
	if err != nil {
		return nil, err
	}

	return &runnerClient{
		knownRunnerUrls: cfg.KnownRunnerInstances,
		httpClient:      utils.NewRetryableHttpClientWithLogging("vssf_runner", logger),
		tokenClient:     tokenClient,
		logger:          logger,
	}, nil
}

func (r *runnerClient) KnownRunnerUrls() []string {
	return r.knownRunnerUrls
}

func (r *runnerClient) GetImageUsage(ctx context.Context, runnerUrl string, imageDefinitionId uint64) (*ImageUsage, error) {
	// Making sure the cached token is up to date.
	err := r.refreshToken(ctx)
	if err != nil {
		return nil, err
	}

	// Get image usage
	// RunnerUrl will have a trailing slash.
	req, err := http.NewRequest("GET", fmt.Sprintf("%s_apis/runner/imageUsage/%d", runnerUrl, imageDefinitionId), nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Authorization", "Bearer "+r.jwtToken)
	resp, err := r.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("failed to get image usage. Status: %s, Body: %s", resp.Status, string(body))
	}
	var imageUsage ImageUsage
	if err := json.NewDecoder(resp.Body).Decode(&imageUsage); err != nil {
		return nil, fmt.Errorf("could not decode ImageUsage JSON: %w", err)
	}

	return &imageUsage, nil
}

func (r *runnerClient) refreshToken(ctx context.Context) error {
	var err error

	if r.jwtToken == "" {
		r.jwtToken, err = r.tokenClient.GetToken(ctx)
		if err != nil {
			return err
		}
	} else {
		// Parse the JWT token
		token, _, err := new(jwt.Parser).ParseUnverified(r.jwtToken, jwt.MapClaims{})
		if err != nil {
			return err
		}

		// Get the expiration time from the token claims
		exp, ok := token.Claims.(jwt.MapClaims)["exp"].(float64)
		if !ok {
			return errors.New("expiration time not found in JWT claims")
		}

		// Convert the expiration time to a time.Time object
		expirationTime := time.Unix(int64(exp), 0)

		// Check if the token is about to expire within the next minute
		if time.Until(expirationTime) < 1*time.Minute {
			// Token is about to expire, refresh it
			r.jwtToken, err = r.tokenClient.GetToken(ctx)
			if err != nil {
				return err
			}
		}
	}

	return nil
}

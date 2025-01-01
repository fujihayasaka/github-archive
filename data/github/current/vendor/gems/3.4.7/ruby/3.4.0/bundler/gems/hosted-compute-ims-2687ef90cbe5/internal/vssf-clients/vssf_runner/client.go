package vssf_runner

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/github/hosted-compute-ims/internal/models"
	"github.com/github/hosted-compute-ims/internal/utils"
	"github.com/github/hosted-compute-ims/internal/vssf-clients/vssf_token"
	"github.com/golang-jwt/jwt/v4"
)

//go:generate mockgen -source=$GOFILE -destination=../../../gen/mocks/mocks_vssf_runner/mock_runner.go -package mocks_runner
type Client interface {
	KnownRunnerUrls() []string
	GetImageUsage(ctx context.Context, runnerUrl string, imageDefinition *models.ImageDefinition) (*ImageUsage, error)
}

type runnerClient struct {
	knownRunnerUrls []string
	httpClient      *utils.RetryableHttpClientWithLogging
	tokenClient     vssf_token.Client
	jwtToken        string
}

func NewClient(cfg *Config, tokenCfg *vssf_token.Config) (Client, error) {
	// Create new runner client
	tokenClient, err := vssf_token.NewClient(tokenCfg)
	if err != nil {
		return nil, err
	}

	return &runnerClient{
		knownRunnerUrls: cfg.KnownRunnerInstances,
		httpClient:      utils.NewRetryableHttpClientWithLogging("vssf_runner"),
		tokenClient:     tokenClient,
	}, nil
}

func (r *runnerClient) KnownRunnerUrls() []string {
	return r.knownRunnerUrls
}

func (r *runnerClient) GetImageUsage(ctx context.Context, runnerUrl string, imageDefinition *models.ImageDefinition) (*ImageUsage, error) {
	runnerImageSource, err := r.getRunnerImageSourceForImageDefinition(imageDefinition)
	if err != nil {
		return nil, fmt.Errorf("failed to get runner image source from image definition: %w", err)
	}

	// Making sure the cached token is up to date.
	if err := r.refreshToken(ctx); err != nil {
		return nil, fmt.Errorf("failed to refresh token: %w", err)
	}

	// Get image usage
	// RunnerUrl will have a trailing slash.
	var req *http.Request

	req, err = http.NewRequest(
		"GET",
		fmt.Sprintf("%s_apis/runner/imageUsage/%d?imageSource=%s", runnerUrl, imageDefinition.Id, runnerImageSource),
		nil,
	)
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

func (r *runnerClient) getRunnerImageSourceForImageDefinition(imageDefinition *models.ImageDefinition) (string, error) {
	// Determine Runner.ImageSource based on IMS image definition:
	// - image definition with Customer image type should use "Custom" ImageSource
	// - image definition with Curated image type and partner owner should use "Marketplace" ImageSource
	// - image definition with Curated image type and github owner should use "Curated" ImageSource
	if imageDefinition.ImageType == models.ImageType_Curated {
		if imageDefinition.OwnerId == models.GithubOwnerId {
			return "Curated", nil
		} else if imageDefinition.OwnerId == models.PartnerOwnerId {
			return "Marketplace", nil
		}
	} else if imageDefinition.ImageType == models.ImageType_Customer {
		return "Custom", nil
	}

	return "", fmt.Errorf("image definition doesn't match any runner image source")
}

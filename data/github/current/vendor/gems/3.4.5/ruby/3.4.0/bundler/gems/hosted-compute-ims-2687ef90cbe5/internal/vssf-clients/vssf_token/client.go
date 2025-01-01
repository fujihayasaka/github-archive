package vssf_token

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/hosted-compute-ims/internal/telemetry/logger"
	"github.com/github/hosted-compute-ims/internal/utils"
)

type Client interface {
	GetToken(ctx context.Context) (string, error)
}
type Service string

type tokenClient struct {
	appID       string
	exchangeURL string
	httpClient  *utils.RetryableHttpClientWithLogging
	pemFile     string
}

func NewClient(cfg *Config) (Client, error) {
	return &tokenClient{
		appID:       "42344e22-4338-4cb6-89a0-7f166bfba0fe",
		exchangeURL: fmt.Sprintf("%s_apis/oauth2/token/0000006F-0000-8888-8000-000000000000", cfg.TokenUrl),
		httpClient:  utils.NewRetryableHttpClientWithLogging("vssf_token"),
		pemFile:     cfg.ImageManagementServicePEM,
	}, nil
}

func (t *tokenClient) GetToken(ctx context.Context) (string, error) {
	logger.Info(ctx, fmt.Sprintf("Getting exchange token from %s", t.exchangeURL))
	duration := time.Minute * 5

	formData, err := GetGrantFormData(t.exchangeURL, t.pemFile, duration, t.appID)
	if err != nil {
		return "", fmt.Errorf("unable to create grant: %w", err)
	}
	accessToken, err := t.sendTokenRequest(ctx, t.exchangeURL, formData)
	if err != nil {
		return "", fmt.Errorf("error in PostForm request for access token: %w", err)
	}

	return accessToken, nil
}

func (t *tokenClient) sendTokenRequest(ctx context.Context, url string, formData url.Values) (string, error) {
	req, err := http.NewRequestWithContext(ctx, "POST", url, strings.NewReader(formData.Encode()))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := t.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer func(Body io.ReadCloser) {
		err := Body.Close()
		if err != nil {
			log.Error("error when closing http response")
		}
	}(resp.Body)

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return "", fmt.Errorf("error getting access token. Status: %s, Body: %s", resp.Status, string(body))
	}
	var accessTokenResponse AccessTokenResponse
	if err := json.NewDecoder(resp.Body).Decode(&accessTokenResponse); err != nil {
		return "", fmt.Errorf("could not decode OAuthExchange JSON: %w", err)
	}
	return accessTokenResponse.AccessToken, nil
}

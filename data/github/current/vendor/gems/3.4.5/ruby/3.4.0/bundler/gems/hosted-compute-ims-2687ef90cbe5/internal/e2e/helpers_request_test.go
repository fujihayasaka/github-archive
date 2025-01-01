package e2e

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"slices"

	twirpAuth "github.com/github/go-twirp/v2/client/auth"
	imagesapi "github.com/github/hosted-compute-ims/gen/twirp/go/services/images_api"
	"github.com/github/hosted-compute-ims/internal/utils"
)

func (s *BaseE2ETestSuite) getHmacHttpClient() imagesapi.HTTPClient {
	var (
		client  imagesapi.HTTPClient
		hmacKey string = os.Getenv("E2E_TWIRP_AUTH_HMAC_KEY")
		err     error
	)

	retryClient := utils.NewRetryableHttpClientWithLogging("e2e_tests")

	if hmacKey != "" {
		client, err = twirpAuth.NewRequestHMACSigner(hmacKey, retryClient)
		s.Require().NoError(err)
	} else {
		client = retryClient
	}

	return client
}

func isOidcAuthAvailable() bool {
	return !slices.Contains([]string{"lab", "internal", "production"}, os.Getenv("ENVIRONMENT"))
}

func (s *BaseE2ETestSuite) getOidcHttpClient() imagesapi.HTTPClient {
	oidcClient := &OidcHttpClient{Client: &http.Client{}}
	httpClient := utils.NewRetryableHttpClientWithLogging("e2e_tests").WithInternalHttpClient(oidcClient)

	return httpClient
}

func getOidcTokenForDevEnvironment() (string, error) {
	// Prepare the data for the POST request
	data := "grant_type=password&username=foo&password=bar&scope=openid"
	requestBody := bytes.NewBufferString(data)

	kubeAddress, err := utils.GetMinikubeIp()
	if err != nil {
		return "", err
	}

	// Create a new request
	req, err := http.NewRequest("POST", fmt.Sprintf("http://%s:28139/token", kubeAddress), requestBody)
	if err != nil {
		return "", err
	}

	// Set the necessary headers
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth("foo", "bar")

	// Make the request using http.Client
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}

	defer resp.Body.Close()

	// Read the response body
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	// Parse the JSON response
	var result map[string]interface{}
	err = json.Unmarshal(body, &result)
	if err != nil {
		return "", err
	}

	// Extract the id_token
	idToken, ok := result["id_token"].(string)
	if !ok {
		return "", fmt.Errorf("unable to extract id_token from response")
	}

	return idToken, nil
}

type OidcHttpClient struct {
	Client *http.Client
}

func (c *OidcHttpClient) Do(req *http.Request) (*http.Response, error) {
	jwtToken, err := getOidcTokenForDevEnvironment()
	if err != nil {
		return nil, err
	}

	req.Header.Set("Authorization", "bearer "+jwtToken)

	return c.Client.Do(req)
}

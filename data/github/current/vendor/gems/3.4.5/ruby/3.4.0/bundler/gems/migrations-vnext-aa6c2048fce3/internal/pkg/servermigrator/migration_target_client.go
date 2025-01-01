package servermigrator

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

const (
	resourcesPath = "/enterprise/migration/resources"
	eventsPath    = "/enterprise/migration/events"
)

// MigrationTargetAPI defines the methods that a migration target client must implement.
type MigrationTargetAPI interface {
	SendResources(ctx context.Context, sourceURL string, resources []*v1.Resource) error
	SendEvents(ctx context.Context, sourceURL string, events []*v1.Event) error
}

// MigrationTargetClient is a client for interacting with the migration target API.
type MigrationTargetClient struct {
	client  *http.Client
	baseURL string
}

type authTransport struct {
	Transport http.RoundTripper
	Token     string
}

func (t *authTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	req.Header.Add("Authorization", "Bearer "+t.Token)
	return t.Transport.RoundTrip(req)
}

// NewMigrationTargetClient creates a new MigrationTargetClient with the given baseURL and token.
func NewMigrationTargetClient(baseURL, token string) *MigrationTargetClient {
	return &MigrationTargetClient{
		client: &http.Client{
			Transport: &authTransport{
				Transport: http.DefaultTransport,
				Token:     token,
			},
		},
		baseURL: baseURL,
	}
}

// SendResources sends the resources to the migration target.
func (c *MigrationTargetClient) SendResources(ctx context.Context, sourceURL string, resources []*v1.Resource) error {
	endpoint := c.baseURL + resourcesPath

	payload, err := json.Marshal(map[string]interface{}{
		"source_url": sourceURL,
		"resources":  resources,
	})
	if err != nil {
		return fmt.Errorf("error marshaling resources: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewBuffer(payload))
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("error sending request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("error sending resources (status %d): %s", resp.StatusCode, body)
	}

	return nil
}

// SendEvents sends the events to the migration target.
func (c *MigrationTargetClient) SendEvents(ctx context.Context, sourceURL string, events []*v1.Event) error {
	endpoint := c.baseURL + eventsPath

	payload, err := json.Marshal(map[string]interface{}{
		"source_url": sourceURL,
		"events":     events,
	})
	if err != nil {
		return fmt.Errorf("error marshaling events: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewBuffer(payload))
	if err != nil {
		return fmt.Errorf("error creating request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.client.Do(req)
	if err != nil {
		return fmt.Errorf("error sending request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusAccepted {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("error sending events (status %d): %s", resp.StatusCode, body)
	}

	return nil
}

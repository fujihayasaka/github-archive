//go:build integration

package integrationtest

import (
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"
)

// TestPingEndpoint tests the server's ping endpoint for health checking
func TestPingEndpoint(t *testing.T) {
	// Get server port from environment or use default
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Build the ping endpoint URL
	pingURL := fmt.Sprintf("http://localhost:%s/_ping", port)

	// Create HTTP client with reasonable timeout
	client := &http.Client{
		Timeout: 2 * time.Second,
	}

	// Make request to ping endpoint
	resp, err := client.Get(pingURL)
	if err != nil {
		t.Fatalf("Failed to make request to ping endpoint: %v", err)
	}
	defer resp.Body.Close()

	// Verify response status code
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, resp.StatusCode)
	}

	// Verify Content-Type header (if the server sets one)
	contentType := resp.Header.Get("Content-Type")
	if contentType != "" {
		t.Logf("Response Content-Type: %s", contentType)
	}
}

// TestReadinessEndpoint tests the server's readiness endpoint for health checking
func TestReadinessEndpoint(t *testing.T) {
	// Get server port from environment or use default
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Build the readiness endpoint URL
	readinessURL := fmt.Sprintf("http://localhost:%s/_ready", port)

	// Create HTTP client with reasonable timeout
	client := &http.Client{
		Timeout: 2 * time.Second,
	}

	// Make request to readiness endpoint
	resp, err := client.Get(readinessURL)
	if err != nil {
		t.Fatalf("Failed to make request to readiness endpoint: %v", err)
	}
	defer resp.Body.Close()

	// Verify response status code
	if resp.StatusCode != http.StatusOK {
		t.Errorf("Expected status code %d, got %d", http.StatusOK, resp.StatusCode)
	}

	// Verify Content-Type header (if the server sets one)
	contentType := resp.Header.Get("Content-Type")
	if contentType != "" {
		t.Logf("Response Content-Type: %s", contentType)
	}
}

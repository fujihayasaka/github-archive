//go:build integration

package integrationtest

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/github/configsd/internal/db"
	"github.com/github/configsd/internal/twirpapi/configs"
	"github.com/github/go-auth/hmac"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// hmacTransport is an HTTP RoundTripper that adds HMAC authentication headers
type hmacTransport struct {
	base    http.RoundTripper
	hmacKey string
}

func (t *hmacTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	// Generate HMAC signature using the key
	req.Header.Set("Request-HMAC", hmac.NewRequestHMAC(t.hmacKey).String())
	return t.base.RoundTrip(req)
}

// seedTestData inserts test configuration data into the database
func seedTestData(t *testing.T, conn *sqlx.DB) {
	// Clean up any existing data
	_, err := conn.Exec("DELETE FROM configuration_entries")
	require.NoError(t, err, "Failed to clean configuration_entries table")

	// Insert test configurations for Business target (ID: 123)
	businessConfigs := []struct {
		name  string
		value string
	}{
		{"feature_flag_enabled", "true"},
		{"max_upload_size", "100MB"},
		{"api_rate_limit", "1000"},
	}

	now := time.Now()
	for _, config := range businessConfigs {
		_, err := conn.Exec(`
			INSERT INTO configuration_entries
			(target_id, target_type, updater_id, name, value, final, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			123, "Business", 1, config.name, config.value, false, now, now)
		require.NoError(t, err, "Failed to insert business config: %s", config.name)
	}

	// Insert test configurations for Global target (ID: 0)
	globalConfigs := []struct {
		name  string
		value string
	}{
		{"maintenance_mode", "false"},
		{"default_timeout", "30s"},
	}

	for _, config := range globalConfigs {
		_, err := conn.Exec(`
			INSERT INTO configuration_entries
			(target_id, target_type, updater_id, name, value, final, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
			0, "Global", 1, config.name, config.value, false, now, now)
		require.NoError(t, err, "Failed to insert global config: %s", config.name)
	}

	t.Logf("Seeded database with %d business configs and %d global configs",
		len(businessConfigs), len(globalConfigs))
}

// setupDatabase connects to the same database as the server and seeds it with test data
func setupDatabase(t *testing.T) {
	// Connect to the same database that the server uses
	dbConn, err := db.NewDbConnectionFromEnvironment()
	require.NoError(t, err, "Failed to connect to database")
	defer dbConn.Close()

	// Seed the database with test data
	seedTestData(t, dbConn)
}

// TestConfigsProtobufClient tests the Configs Twirp service using the generated Protobuf client
func TestConfigsProtobufClient(t *testing.T) {
	// Setup database with test data
	setupDatabase(t)

	// Get server port from environment or use default
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Build the base URL for the server
	baseURL := fmt.Sprintf("http://localhost:%s", port)

	// Get HMAC key from environment
	hmacKey := os.Getenv("APP_HMAC_KEY_PRIMARY")
	require.NotEmpty(t, hmacKey, "APP_HMAC_KEY_PRIMARY must be set")

	// Create HTTP client with HMAC header transport
	httpClient := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &hmacTransport{
			base:    http.DefaultTransport,
			hmacKey: hmacKey,
		},
	}

	// Create Twirp Protobuf client
	client := configs.NewConfigsProtobufClient(baseURL, httpClient)

	// Create request with a business target (ID: 123, which we seeded with data)
	req := &configs.ResolveConfigsByTargetRequest{
		Target: &configs.ConfigTarget{
			Id:   123,
			Type: configs.TargetType_Business,
		},
	}

	// Create context with timeout
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()

	// Make request to Configs service
	resp, err := client.ResolveConfigsByTarget(ctx, req)
	require.NoError(t, err, "Failed to call ResolveConfigsByTarget service")

	// Validate response
	assert.NotNil(t, resp, "Response should not be nil")
	require.NotNil(t, resp.Configs, "Configs map should not be nil")

	// Verify we received the expected business configurations
	assert.GreaterOrEqual(t, len(resp.Configs.Configs), 3, "Should have at least 3 business configs")

	// Check for specific configurations we seeded
	assert.Contains(t, resp.Configs.Configs, "feature_flag_enabled")
	assert.Contains(t, resp.Configs.Configs, "max_upload_size")
	assert.Contains(t, resp.Configs.Configs, "api_rate_limit")

	// Verify the values
	if config, exists := resp.Configs.Configs["feature_flag_enabled"]; exists {
		assert.Equal(t, "true", config.Value, "feature_flag_enabled should be 'true'")
	}
	if config, exists := resp.Configs.Configs["max_upload_size"]; exists {
		assert.Equal(t, "100MB", config.Value, "max_upload_size should be '100MB'")
	}
	if config, exists := resp.Configs.Configs["api_rate_limit"]; exists {
		assert.Equal(t, "1000", config.Value, "api_rate_limit should be '1000'")
	}

	t.Logf("Successfully called ResolveConfigsByTarget service with Protobuf client, received %d configs", len(resp.Configs.Configs))
}

// TestConfigsProtobufClient_NoHMAC tests that requests fail when HMAC header is not present
func TestConfigsProtobufClient_NoHMAC(t *testing.T) {
	// Setup database with test data
	setupDatabase(t)

	// Get server port from environment or use default
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Build the base URL for the server
	baseURL := fmt.Sprintf("http://localhost:%s", port)

	// Create HTTP client WITHOUT HMAC header transport
	httpClient := &http.Client{
		Timeout: 5 * time.Second,
	}

	// Create Twirp Protobuf client
	client := configs.NewConfigsProtobufClient(baseURL, httpClient)

	// Create request with a business target (ID: 123, which we seeded with data)
	req := &configs.ResolveConfigsByTargetRequest{
		Target: &configs.ConfigTarget{
			Id:   123,
			Type: configs.TargetType_Business,
		},
	}

	// Create context with timeout
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()

	// Make request to Configs service - should fail due to missing HMAC
	resp, err := client.ResolveConfigsByTarget(ctx, req)

	// Verify that the request failed
	require.Error(t, err, "Request should fail when HMAC header is missing")
	assert.Nil(t, resp, "Response should be nil on authentication failure")
	assert.Contains(t, err.Error(), "unauthenticated", "Error should indicate authentication failure")

	t.Logf("Successfully verified that request fails without HMAC header: %v", err)
}

// TestConfigsProtobufClient_WrongHMAC tests that requests fail when HMAC header is incorrect
func TestConfigsProtobufClient_WrongHMAC(t *testing.T) {
	// Setup database with test data
	setupDatabase(t)

	// Get server port from environment or use default
	port := os.Getenv("APP_PORT")
	if port == "" {
		port = "8080"
	}

	// Build the base URL for the server
	baseURL := fmt.Sprintf("http://localhost:%s", port)

	// Create HTTP client with WRONG HMAC key
	httpClient := &http.Client{
		Timeout: 5 * time.Second,
		Transport: &hmacTransport{
			base:    http.DefaultTransport,
			hmacKey: "wrong_secret_key", // This is incorrect
		},
	}

	// Create Twirp Protobuf client
	client := configs.NewConfigsProtobufClient(baseURL, httpClient)

	// Create request with a business target (ID: 123, which we seeded with data)
	req := &configs.ResolveConfigsByTargetRequest{
		Target: &configs.ConfigTarget{
			Id:   123,
			Type: configs.TargetType_Business,
		},
	}

	// Create context with timeout
	ctx, cancel := context.WithTimeout(t.Context(), 5*time.Second)
	defer cancel()

	// Make request to Configs service - should fail due to wrong HMAC
	resp, err := client.ResolveConfigsByTarget(ctx, req)

	// Verify that the request failed
	require.Error(t, err, "Request should fail when HMAC header is incorrect")
	assert.Nil(t, resp, "Response should be nil on authentication failure")
	assert.Contains(t, err.Error(), "unauthenticated", "Error should indicate authentication failure")

	t.Logf("Successfully verified that request fails with wrong HMAC key: %v", err)
}

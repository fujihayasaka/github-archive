package httputil

import (
	"encoding/base64"
	"net"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

func TestSimpleHTTPClientCreate(t *testing.T) {
	client, err := NewClient(nil)

	require.NoError(t, err)
	require.NotNil(t, client)
}

func TestHTTPClientCreate(t *testing.T) {
	headers := http.Header{"X-Eli-Testing": {"yiss"}}
	client, err := NewClient(
		headers,
		WithKeepAlive(500*time.Millisecond),
		WithCompression(false),
	)

	require.NoError(t, err)
	require.NotNil(t, client)
}

func TestHTTPConfigureTLS(t *testing.T) {
	client, transport, dialer := setup(t)
	keyPEM, err := fetchTestCredential(t, "testdata/key.data")
	require.NoError(t, err)
	certPEM, err := fetchTestCredential(t, "testdata/cert.data")
	require.NoError(t, err)
	var optionalCABundle string

	option := WithTLSFromEnv(keyPEM, certPEM, optionalCABundle)
	err = option(client, transport, dialer)

	require.NoError(t, err)
	require.NotNil(t, transport.TLSClientConfig)
}

func TestHTTPConfigureKeepAlive(t *testing.T) {
	expectedKeepAlive := 11 * time.Second
	client, transport, dialer := setup(t)

	option := WithKeepAlive(expectedKeepAlive)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedKeepAlive, dialer.KeepAlive)
}

func TestHTTPConfigureConnectTimeout(t *testing.T) {
	expectedTimeout := 22 * time.Second
	client, transport, dialer := setup(t)

	option := WithConnectTimeout(expectedTimeout)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedTimeout, dialer.Timeout)
}

func TestHTTPConfigureTLSHandshakeTimeout(t *testing.T) {
	expectedHandshakeTimeout := 33 * time.Second
	client, transport, dialer := setup(t)

	option := WithTLSHandshakeTimeout(expectedHandshakeTimeout)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedHandshakeTimeout, transport.TLSHandshakeTimeout)
}

func TestHTTPResponseHeaderTimeout(t *testing.T) {
	expectedResponseHeaderTimeout := 44 * time.Second
	client, transport, dialer := setup(t)

	option := WithResponseHeaderTimeout(expectedResponseHeaderTimeout)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedResponseHeaderTimeout, transport.ResponseHeaderTimeout)
}

func TestHTTPConfigureRequestTimeout(t *testing.T) {
	expectedTimeout := 55 * time.Second
	client, transport, dialer := setup(t)

	option := WithRequestTimeout(expectedTimeout)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedTimeout, client.Timeout)
}

func TestHTTPMaxIdleConns(t *testing.T) {
	expected := 66
	client, transport, dialer := setup(t)

	option := WithMaxIdleConns(expected)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expected, transport.MaxIdleConns)
}

func TestHTTPMaxIdleConnsPerHost(t *testing.T) {
	expected := 77
	client, transport, dialer := setup(t)

	option := WithMaxIdleConnsPerHost(expected)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expected, transport.MaxIdleConnsPerHost)
}

func TestHTTPMaxConnsPerHost(t *testing.T) {
	expected := 88
	client, transport, dialer := setup(t)

	option := WithMaxConnsPerHost(expected)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expected, transport.MaxConnsPerHost)
}

func TestHTTPConfigureIdleConnTimeout(t *testing.T) {
	expectedTimeout := 99 * time.Second
	client, transport, dialer := setup(t)

	option := WithIdleConnTimeout(expectedTimeout)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedTimeout, transport.IdleConnTimeout)
}

func TestHTTPConfigureCompression(t *testing.T) {
	// trial one - enable
	enableCompression := true
	expectedSetting := !enableCompression
	client, transport, dialer := setup(t)

	option := WithCompression(enableCompression)
	err := option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedSetting, transport.DisableCompression)

	// trial two - disable
	disableCompression := false
	expectedSetting = !disableCompression
	client, transport, dialer = setup(t)

	option = WithCompression(disableCompression)
	err = option(client, transport, dialer)

	require.NoError(t, err)
	require.Equal(t, expectedSetting, transport.DisableCompression)
}

func setup(t *testing.T) (*http.Client, *http.Transport, *net.Dialer) {
	t.Helper()
	return &http.Client{}, &http.Transport{}, &net.Dialer{}
}

// given a file path: read the file, decode the base64 payload,
// and return the output as a string
func fetchTestCredential(t *testing.T, path string) (string, error) {
	t.Helper()

	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	pem, err := base64.StdEncoding.DecodeString(string(data))

	return string(pem), err
}

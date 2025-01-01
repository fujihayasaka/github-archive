package hmac

import (
	"bytes"
	"context"
	"encoding/base64"
	"fmt"
	"log"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/utils/testutils"
)

const (
	hmacTestKey          = "hmacTestkey"
	httpsScheme          = "https"
	vaultTypeKeyFetcher  = "vaultTypeKeyFetcher"
	configTypeKeyFetcher = "configTypeKeyFetcher"
)

func TestHTTPVerifierWithKeyFetcher(t *testing.T) {
	var configKeyFetcher KeyFetcher
	var err error
	authVerifier := NewVerifier(NewSigner())
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	tests := []struct {
		name           string
		hmacKey        string
		keyFetcherType string
		errExpected    bool
		errMessage     string
	}{
		{
			name:           "success when hmac key is set correctly in config",
			hmacKey:        base64.StdEncoding.EncodeToString([]byte(hmacTestKey)),
			keyFetcherType: configTypeKeyFetcher,
		},
		{
			name:           "success when hmac key is set correctly in vault",
			hmacKey:        hmacTestKey,
			keyFetcherType: vaultTypeKeyFetcher,
		},
		{
			name:           "Fail when hmac key is set incorrectly in config",
			hmacKey:        base64.StdEncoding.EncodeToString([]byte("wrongKey")),
			keyFetcherType: configTypeKeyFetcher,
			errExpected:    true,
			errMessage:     "invalid signature",
		},
		{
			name:           "Fail when hmac key is set incorrectly in vault",
			hmacKey:        "WrongKey",
			keyFetcherType: vaultTypeKeyFetcher,
			errExpected:    true,
			errMessage:     "invalid signature",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			if tc.keyFetcherType == vaultTypeKeyFetcher {
				keyVaultClient := &azp.MockKeyVaultClient{}
				keyVaultClient.EXPECT().GetSecret(mock.Anything, mock.Anything, mock.Anything).Return(makeKeyVaultSecret([]byte(tc.hmacKey)), nil)
				configKeyFetcher = NewVaultKeyFetcher("", "", "", keyVaultClient)
			} else {
				configKeyFetcher, err = NewConfigKeyFetcher(tc.hmacKey, tc.hmacKey)
				require.NoError(t, err)
			}
			httpVerifier := NewHTTPVerifier(configKeyFetcher, obs, authVerifier, httpsScheme)
			err = httpVerifier.Verify(context.Background(), getRequest("{}", hmacTestKey), []byte("{}"))
			if tc.errExpected {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), tc.errMessage)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func TestHTTPVerifierWithVariousURLs(t *testing.T) {
	tests := []struct {
		name string
		// the url the caller used to make the request, and signed
		signedURL   string
		requestHost string
		// the path in the launch-receiver request
		requestTarget string
	}{
		{
			// This is the simplest case, but based on debugging of real requests in the dev environment, the scheme and host are usually not specified in request.URL.
			name:          "full request target",
			signedURL:     "https://localhost/actions/path",
			requestTarget: "https://localhost/actions/path",
		},
		{
			name:          "basic path",
			signedURL:     "https://localhost/actions/path",
			requestHost:   "localhost",
			requestTarget: "/actions/path",
		},
		{
			name:          "path with query string",
			signedURL:     "https://localhost/actions/path?foo=bar",
			requestHost:   "localhost",
			requestTarget: "/actions/path?foo=bar",
		},
		{
			name:          "escaped path",
			signedURL:     "https://localhost/actions/path%20with%20spaces",
			requestHost:   "localhost",
			requestTarget: "/actions/path%20with%20spaces",
		},
		{
			name:          "path segment with escaped reserved characters (ac/dc)",
			signedURL:     "https://localhost/artist/ac%2Fdc",
			requestHost:   "localhost",
			requestTarget: "/artist/ac%2Fdc",
		},
		{
			name:          "path segment with escaped reserved characters (2+2=4)",
			signedURL:     "https://localhost/math/2%2B2%3D4",
			requestHost:   "localhost",
			requestTarget: "/math/2%2B2%3D4",
		},
		{
			name: "path that should be escaped per RFC 2396",
			// the caller should have signed the escaped version of the url, per ADR 0606, https://github.com/github/c2c-actions/blob/main/docs/adrs/0606-add-documentation-of-hmac-signing.md.
			signedURL:     "https://localhost/actions/foo%5Ebar",
			requestHost:   "localhost",
			requestTarget: "/actions/foo^bar",
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			authVerifier := NewVerifier(NewSigner())
			obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
			hmacKey := base64.StdEncoding.EncodeToString([]byte(hmacTestKey))
			configKeyFetcher, err := NewConfigKeyFetcher(hmacKey, hmacKey)
			require.NoError(tt, err)
			httpVerifier := NewHTTPVerifier(configKeyFetcher, obs, authVerifier, httpsScheme)
			req := constructHttpRequest(tc.requestHost, tc.requestTarget, tc.signedURL, "{}", hmacTestKey)
			err = httpVerifier.Verify(context.Background(), req, []byte("{}"))
			require.NoError(tt, err)
		})
	}
}

func TestHTTPVerifierWithoutAuthorizationHeader(t *testing.T) {
	authVerifier := NewVerifier(NewSigner())
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	httpVerifier := NewHTTPVerifier(nil, obs, authVerifier, httpsScheme)
	req := getRequest("{}", hmacTestKey)
	req.Header.Del("Authorization")
	err := httpVerifier.Verify(context.Background(), req, []byte("{}"))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "authorization header not found or invalid")
}

func TestHTTPVerifierInvalidHeaderSignatureRegex(t *testing.T) {
	authVerifier := NewVerifier(NewSigner())
	obs := observability.New(testutils.NewRecordingLogger().Logger, statter.NullStatter())
	httpVerifier := NewHTTPVerifier(nil, obs, authVerifier, httpsScheme)
	req := getRequest("{}", hmacTestKey)
	req.Header.Set("Authorization", "test test")
	err := httpVerifier.Verify(context.Background(), req, []byte("{}"))
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "authorization header not found or invalid")
}

func getRequest(body, signature string) *http.Request {
	return constructHttpRequest("localhost", "/actions/path", "https://localhost/actions/path", body, signature)
}

func constructHttpRequest(host, requestTarget, urlUsedByCaller, body, signature string) *http.Request {
	req := httptest.NewRequest(http.MethodGet, requestTarget, bytes.NewReader([]byte(body)))
	if host != "" {
		req.Host = host
	}

	var msg bytes.Buffer
	_, _ = msg.WriteString(urlUsedByCaller)
	_, _ = msg.WriteRune('\n')
	_, _ = msg.Write([]byte(body))
	data := msg.Bytes()
	log.Print(signature)

	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte(NewSigner().Sign([]byte(signature), data)))))
	req.Header.Add("Content-Type", "application/json")
	if host != "" {
		req.Header.Add("Host", host)
	}
	return req
}

func makeKeyVaultSecret(pwd []byte) *azp.KeyVaultSecret {
	val := fmt.Sprintf(`{"Password":"%s"}`, base64.StdEncoding.EncodeToString(pwd))
	return &azp.KeyVaultSecret{
		Value: val,
	}
}

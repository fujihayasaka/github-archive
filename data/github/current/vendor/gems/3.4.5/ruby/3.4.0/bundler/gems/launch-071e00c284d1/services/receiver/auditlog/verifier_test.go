package auditlog

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/auth/hmac"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/db/stores/deployer"
	"github.com/github/launch/hydro/events"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/azp"
)

func TestVerifier(t *testing.T) {
	signatureKey := "signature"

	tests := []struct {
		name                             string
		cfg                              *Config
		errorMsg                         string
		vaultActionsAuthHmacKeyPrimary   string
		vaultActionsAuthHmacKeySecondary string
	}{
		{
			name: "success when primary key is set correctly in enterprise",
			cfg: &Config{
				IsEnterprise:              true,
				ActionsAuthHmacKeyPrimary: base64.StdEncoding.EncodeToString([]byte("signature")),
			},
		},
		{
			name: "success when only secondary key is set correctly in enterprise",
			cfg: &Config{
				IsEnterprise:                true,
				ActionsAuthHmacKeySecondary: base64.StdEncoding.EncodeToString([]byte("signature")),
			},
		},
		{
			name: "failure when both primary and secondary keys are not correct values in enterprise",
			cfg: &Config{
				IsEnterprise:                true,
				ActionsAuthHmacKeyPrimary:   base64.StdEncoding.EncodeToString([]byte("random-string1")),
				ActionsAuthHmacKeySecondary: base64.StdEncoding.EncodeToString([]byte("random-string2")),
			},
			errorMsg: "Invalid signature",
		},
		{
			name: "failure when both primary and secondary keys are empty in enterprise",
			cfg: &Config{
				IsEnterprise: true,
			},
			errorMsg: "ActionsAuthHmacKeySecondary is not set in the configuration",
		},
		{
			name: "failure when both primary an secondary keys are non-base64 string in enterprise",
			cfg: &Config{
				IsEnterprise:                true,
				ActionsAuthHmacKeyPrimary:   "signature",
				ActionsAuthHmacKeySecondary: "signature",
			},
			errorMsg: "illegal base64 data",
		},
		{
			name: "success when non enterprise",
			cfg: &Config{
				IsEnterprise: false,
			},
			vaultActionsAuthHmacKeyPrimary: base64.StdEncoding.EncodeToString([]byte("signature")),
		},
		{
			name: "failure when invalid signature in non enterprise",
			cfg: &Config{
				IsEnterprise: false,
			},
			vaultActionsAuthHmacKeyPrimary:   base64.StdEncoding.EncodeToString([]byte("wrongsignature1")),
			vaultActionsAuthHmacKeySecondary: base64.StdEncoding.EncodeToString([]byte("wrongsignature2")),
			errorMsg:                         "Invalid signature",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(tt *testing.T) {
			vaultName := "some vault name"
			keyVaultClient := &azp.MockKeyVaultClient{}
			if !tc.cfg.IsEnterprise {
				primarySecret := &azp.KeyVaultSecret{
					Value: fmt.Sprintf(`{"Password":"%s"}`, tc.vaultActionsAuthHmacKeyPrimary)}
				secondarySecret := &azp.KeyVaultSecret{
					Value: fmt.Sprintf(`{"Password":"%s"}`, tc.cfg.ActionsAuthHmacKeySecondary)}
				keyVaultClient.On("GetSecret", mock.Anything, vaultName, primaryHMACKeyName).
					Return(primarySecret, nil)
				keyVaultClient.On("GetSecret", mock.Anything, vaultName, secondaryHMACKeyName).
					Return(secondarySecret, nil)
			}

			svc := NewService(
				tc.cfg,
				observability.NewNullObservability(),
				&events.MockHydro{},
				&deployer.MockAzpResourcesLoader{},
				vaultName,
				keyVaultClient,
				hmac.NewVerifier(hmac.NewSigner()),
				&ghtwirp.MockClient{},
			)

			data, _ := json.Marshal(exampleWorkflowJopPrepared)
			req := getRequest(string(data), signatureKey, tc.cfg.IsEnterprise)
			body, _ := io.ReadAll(req.Body)

			err := svc.verifyRequestSignature(context.Background(), req, body)
			if tc.errorMsg == "" {
				require.NoError(tt, err)
			} else {
				assert.Error(tt, err)
				assert.Contains(tt, err.Error(), tc.errorMsg)
			}
		})
	}
}

func getRequest(body, signature string, isEnterprise bool) *http.Request {
	scheme := "https"
	if isEnterprise {
		scheme = "http"
	}
	uri := fmt.Sprintf("%s://localhost/actions/workflow_job/prepared", scheme)
	req := httptest.NewRequest(http.MethodGet, uri, bytes.NewReader([]byte(body)))

	var msg bytes.Buffer
	_, _ = msg.Write([]byte(uri))
	_, _ = msg.Write([]byte("\n"))
	_, _ = msg.Write([]byte(body))
	data := msg.Bytes()

	req.Header.Add("Authorization", fmt.Sprintf("HMAC-SHA512 Signature=%s", base64.StdEncoding.EncodeToString([]byte(hmac.NewSigner().Sign([]byte(signature), data)))))
	req.Header.Add("Content-Type", "application/json")

	return req
}

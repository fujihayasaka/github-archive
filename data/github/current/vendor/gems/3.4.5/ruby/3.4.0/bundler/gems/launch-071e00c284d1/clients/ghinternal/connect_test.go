package ghinternal

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/github/tokens"
	"github.com/github/launch/observability"
	"github.com/github/launch/pkg/launchhttp/httpclient"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/testutils"
)

func TestGetConnectToken(t *testing.T) {
	tests := []struct {
		desc          string
		errExpected   bool
		statusCode    int
		expectedToken string
		wantErr       error
	}{
		{
			desc:          "returns the token for a proper request",
			statusCode:    http.StatusOK,
			expectedToken: "test-bearer-token",
		},
		{
			desc:        "does not return a token and returns ErrConnectNotEnabled for 404s",
			statusCode:  http.StatusNotFound,
			errExpected: true,
			wantErr:     ErrConnectNotEnabled,
		},
		{
			desc:        "does not return a token for 500s",
			statusCode:  http.StatusInternalServerError,
			errExpected: true,
		},
		{
			desc:        "does not return a token and returns ErrConnectNotEnabled for 418s",
			statusCode:  http.StatusPreconditionFailed,
			errExpected: true,
			wantErr:     ErrConnectNotEnabled,
		},
	}

	for _, tt := range tests {
		t.Run(tt.desc, func(t *testing.T) {
			ctx := context.Background()
			ctx, cancel := context.WithTimeout(ctx, time.Second)
			defer cancel()

			_, url, teardown := newRemoteServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				require.Equal(t, r.URL.Path, "/enterprise/actions-token")
				require.Equal(t, "Bearer test-token", r.Header.Get("Authorization"))
				w.WriteHeader(tt.statusCode)
				// Don't write a response for error codes
				if tt.statusCode >= 400 {
					return
				}
				// Always return a token
				_, _ = w.Write([]byte(`{
					"token": "test-bearer-token",
					"expires_at": "2020-06-12T16:44:50Z",
					"permissions": {},
					"repository_selection": "selected"
				}`))
			}))
			defer teardown()

			cf := NewFactory(url, observability.NewNullObservability(), testutils.NewNoopBreaker(), []byte("testsigningkey"), apphttp.NewClient(), httpclient.NewClientHooks())
			client, err := cf.CreateWithAccessToken(&tokens.AccessToken{
				Token:  "test-token",
				Expiry: time.Now(),
			})
			require.NoError(t, err)

			token, err := client.GetConnectToken(ctx)
			if tt.errExpected {
				require.Error(t, err)
				if tt.wantErr != nil {
					require.Equal(t, tt.wantErr, err)
				}
			} else {
				require.NoError(t, err)
				require.Equal(t, tt.expectedToken, token.Token)
			}
		})
	}

}

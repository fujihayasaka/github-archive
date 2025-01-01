package api

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/proto"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

type badServer struct {
	proto.AdvancedSecurityAPI
}

func (s badServer) GetSummary(context.Context, *proto.GetSummaryRequest) (*proto.GetSummaryResponse, error) {
	return nil, errors.New("boom")
}

func TestServerOptions(t *testing.T) {
	var called bool

	// prove that it doesn't seem to matter which order the hooks and interceptors are passed in and
	// that they correctly add entity information to the error
	next := proto.NewAdvancedSecurityAPIServer(badServer{}, twirp.WithServerHooks(&twirp.ServerHooks{
		Error: func(ctx context.Context, e twirp.Error) context.Context {
			called = true
			require.ElementsMatch(t, fields.From(e), []kvp.Field{
				kvp.Uint64("turboghas.entity_id", 1),
				kvp.String("turboghas.entity_type", "ENTITY_TYPE_BUSINESS"),
			})
			return ctx
		},
	}), twirp.WithServerInterceptors(
		rewriteInvalidConnection,
		addEntityToError,
	))

	rec := httptest.NewRecorder()
	req, err := http.NewRequest(
		"POST",
		"http://localhost:8866/twirp/github.turboghas.AdvancedSecurityAPI/GetSummary",
		strings.NewReader(`{"entity_id": 1, "entity_type": "ENTITY_TYPE_BUSINESS"}`),
	)
	req.Header.Set("Content-Type", "application/json")
	require.NoError(t, err)

	next.ServeHTTP(rec, req)

	require.True(t, called)
}

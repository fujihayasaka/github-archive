package ghinternal

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/clients/github/tokens"
	hydro "github.com/github/launch/hydro/schemas/github/actions/v0"
	"github.com/github/launch/observability"
	lerrors "github.com/github/launch/types/errors"

	"github.com/github/launch/types"
	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/testutils"
)

func TestDoRunsAJSONRequest(t *testing.T) {
	type request struct {
		Name   string
		Nested struct {
			Ok bool
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/ok", func(w http.ResponseWriter, r *http.Request) {
		var input request
		err := json.NewDecoder(r.Body).Decode(&input)
		require.NoError(t, err)
		assert.Equal(t, "Molly", input.Name)
		assert.Equal(t, true, input.Nested.Ok)
		fmt.Fprintf(w, "")
	})
	_, url, teardown := newRemoteServer(mux)
	defer teardown()

	obs := observability.NewNullObservability()
	c := New(
		url,
		apphttp.NewClient(),
		obs,
	)
	err := c.do(context.Background(), "test-one", "POST", "ok", request{
		Name: "Molly",
		Nested: struct {
			Ok bool
		}{true},
	}, nil, nil)
	require.NoError(t, err)
}

func TestRequestConfigurationHook(t *testing.T) {
	uaString := "Tessier-Ashpool Browser Mk3"
	mux := http.NewServeMux()
	mux.HandleFunc("/with-ua", func(w http.ResponseWriter, r *http.Request) {
		assert.Equal(t, uaString, r.Header.Get("user-agent"))
		fmt.Fprintf(w, "")
	})
	_, url, teardown := newRemoteServer(mux)
	defer teardown()

	withExampleUA := func(r *http.Request) error {
		r.Header.Set("User-Agent", uaString)
		return nil
	}

	obs := observability.NewNullObservability()
	c := New(
		url,
		apphttp.NewClient(),
		obs,
		WithRequestOptions(withExampleUA),
	)
	err := c.do(context.Background(), "test-one", "POST", "with-ua", "", nil, nil)
	require.NoError(t, err)
}

func TestRequestConfigurationHookWhichErrors(t *testing.T) {
	withFailable := func(r *http.Request) error {
		return errors.New("failed")
	}

	obs := observability.NewNullObservability()
	c := New(
		&url.URL{},
		apphttp.NewClient(),
		obs,
		WithRequestOptions(withFailable),
	)
	err := c.do(context.Background(), "test-one", "POST", "fail", "", nil, nil)
	require.Contains(t, err.Error(), "failed")
}

func TestTracing(t *testing.T) {
	opName := "test-operation-name"
	sns := testutils.CollectFinishedSpanNames(func() {
		_, url, teardown := newRemoteServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			require.Equal(t, r.URL.Path, "/ping")
			fmt.Fprintf(w, "pong")
		}))
		defer teardown()

		obs := observability.NewNullObservability()
		c := New(
			url,
			apphttp.NewClient(),
			obs,
		)
		err := c.do(context.Background(), opName, "POST", "ping", "", nil, nil)
		require.NoError(t, err)
	})

	assert.Contains(t, sns, "ghinternal/(*ghclient)."+opName)
}

func TestConfigureRequestCanBeUsedWithStandardRequestObjects(t *testing.T) {
	// this test demonstrates how to compose the client with a request not created via one of
	// its `New...Request()` methods
	_, url, teardown := newRemoteServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.Equal(t, r.URL.Path, "/patch")
		all, err := io.ReadAll(r.Body)
		require.NoError(t, err)
		assert.Equal(t, `"hello"`, string(all))
		fmt.Fprintf(w, "pong")
	}))
	defer teardown()

	obs := observability.NewNullObservability()
	c := New(
		url,
		apphttp.NewClient(),
		obs,
	)

	err := c.do(context.Background(), "patchOp", "PATCH", "/patch", "hello", nil, nil)
	require.NoError(t, err)
}

// newRemoteServer boots up a server. It returns a mux, its url, and a teardown function.
func newRemoteServer(hdl http.Handler) (*httptest.Server, *url.URL, func()) {
	server := httptest.NewServer(hdl)
	urlProvider, err := url.Parse(server.URL)
	if err != nil {
		panic(err)
	}
	return server, urlProvider, server.Close
}

func init() {
	testutils.EnsureGlobalTracerIsMocked()
}

func TestClient(t *testing.T) {
	obs := observability.NewNullObservability()
	testClient(t, func(t *testing.T, srv *url.URL) Client {
		base, err := srv.Parse("/api/v3/")
		require.NoError(t, err)
		return New(base, &http.Client{}, obs)
	})
}

func testClient(t *testing.T, makeClient func(t *testing.T, srv *url.URL) Client) {
	headerKeys := []string{"Accept-Encoding", "X-Glb-Via"}

	now := time.Now().Truncate(time.Second).UTC()
	nowJSON := now.Format(time.RFC3339)
	ctx := context.Background()

	userID := types.GlobalID("U_kgDOAP3FAg")  // 16631042
	businessID := types.GlobalID("E_kgDNLMw") // 11468

	type req struct {
		method  string
		headers http.Header
		url     string
		body    string
	}
	type resp struct {
		code    int
		headers http.Header
		body    string
	}
	tests := []struct {
		name         string
		doRequest    func(Client) (any, error)
		wantReq      req
		wantReqCount int
		sendResp     resp
		wantResp     any
		checkErr     func(t *testing.T, srv *httptest.Server, err error)
	}{
		// - GetConnectToken
		{
			name: "GetConnectToken - happy path",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetConnectToken(ctx)
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"0"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/enterprise/actions-token",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    200,
				headers: make(http.Header),
				body:    `{"token":"hello", "expires_at": "` + nowJSON + `"}`,
			},
			wantResp: &tokens.AccessToken{
				Token:  "hello",
				Expiry: now,
			},
		},
		{
			name: "GetConnectToken - 404 path",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetConnectToken(ctx)
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"0"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/enterprise/actions-token",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    http.StatusNotFound,
				headers: make(http.Header),
			},
			wantResp: (*tokens.AccessToken)(nil),
			checkErr: checkErrMustBe(ErrConnectNotEnabled),
		},
		{
			name: "GetConnectToken - 412 path",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetConnectToken(ctx)
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"0"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/enterprise/actions-token",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    http.StatusPreconditionFailed,
				headers: make(http.Header),
			},
			wantResp: (*tokens.AccessToken)(nil),
			checkErr: checkErrMustBe(ErrConnectNotEnabled),
		},
		{
			name: "GetConnectToken - other 4xx error codes",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetConnectToken(ctx)
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"0"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/enterprise/actions-token",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    401,
				headers: make(http.Header),
			},
			wantResp: (*tokens.AccessToken)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, got error) {
				res := &http.Response{
					StatusCode: 401,
					Request: &http.Request{URL: &url.URL{
						Scheme: "http",
						Host:   srv.Listener.Addr().String(),
						Path:   "/api/v3/enterprise/actions-token",
					}},
				}
				want := lerrors.NewHTTPError(res)
				require.Equal(t, want, got)
			},
		},
		{
			name: "GetConnectToken - other 5xx error codes",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetConnectToken(ctx)
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"0"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/enterprise/actions-token",
				body: ``,
			},
			wantReqCount: 4, // it should retry
			sendResp: resp{
				code:    503,
				headers: make(http.Header),
			},
			wantResp: (*tokens.AccessToken)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, got error) {
				require.Error(t, got)
			},
		},
		// - GetAbuseDataForHydro
		{
			name: "GetAbuseDataForHydro - happy path",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetAbuseDataForHydro(ctx, []types.GlobalID{userID, businessID})
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"36"},
					"Content-Type":   []string{"application/json"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/internal/actions/abuse-batch-info",
				body: fmt.Sprintf(`{"ids":["%s","%s"]}`, userID, businessID),
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    200,
				headers: make(http.Header),
				body:    fmt.Sprintf(`{"owners_by_id":{"%s":{"id":"%s"},"%s":{"id":"%s"}}}`, userID, userID, businessID, businessID),
			},
			wantResp: &AbuseDataForHydro{OwnersByEntityID: map[types.GlobalID]*hydro.BillingPlanOwner{
				userID:     {GlobalId: userID.String()},
				businessID: {GlobalId: businessID.String()},
			}},
		},
		{
			name: "GetAbuseDataForHydro - no entity",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetAbuseDataForHydro(ctx, []types.GlobalID{})
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"10"},
					"Content-Type":   []string{"application/json"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/internal/actions/abuse-batch-info",
				body: `{"ids":[]}`,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    200,
				headers: make(http.Header),
				body:    `{"owners_by_id":{}}`,
			},
			wantResp: &AbuseDataForHydro{OwnersByEntityID: map[types.GlobalID]*hydro.BillingPlanOwner{}},
		},
		{
			name: "GetAbuseDataForHydro - other 4xx error codes",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetAbuseDataForHydro(ctx, []types.GlobalID{userID, businessID})
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"36"},
					"Content-Type":   []string{"application/json"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/internal/actions/abuse-batch-info",
				body: fmt.Sprintf(`{"ids":["%s","%s"]}`, userID, businessID),
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    http.StatusNotFound,
				headers: make(http.Header),
			},
			wantResp: (*AbuseDataForHydro)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, got error) {
				require.Error(t, got)
			},
		},
		{
			name: "GetAbuseDataForHydro - other 5xx error codes",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.GetAbuseDataForHydro(ctx, []types.GlobalID{"hello", "world"})
				return r, err
			},
			wantReq: req{
				method: http.MethodPost,
				headers: http.Header{
					"Content-Length": []string{"25"},
					"Content-Type":   []string{"application/json"},
					"User-Agent":     []string{"launch-ghclient"},
				},
				url:  "/api/v3/internal/actions/abuse-batch-info",
				body: `{"ids":["hello","world"]}`,
			},
			wantReqCount: 4, // it should retry
			sendResp: resp{
				code:    503,
				headers: make(http.Header),
			},
			wantResp: (*AbuseDataForHydro)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, got error) {
				require.Error(t, got)
			},
		},
		// - ResolveAction
		{
			name: "ResolveAction - happy path",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.ResolveAction(ctx, "some_nwo", "some_gitref", 42, "some_job_id", 14)
				return r, err
			},
			wantReq: req{
				method: http.MethodGet,
				headers: http.Header{
					"User-Agent": []string{"launch-ghclient"},
				},
				url:  "/api/v3/repos/some_nwo/actions/resolve/some_gitref?jobId=some_job_id&workflowRepoId=14&workflowRunId=42",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    200,
				headers: make(http.Header),
				body:    `{"name":"a_name","resolved_name":"a_res_name","resolved_sha":"a_sha","tag_url":"a_url","zip_url":"a_z_url","version":"a_version"}`,
			},
			wantResp: &ResolvedAction{Name: "some_nwo", ResolvedName: "a_res_name", ResolvedSha: "a_sha", TarURL: "", ZipURL: "a_z_url", Version: "a_version"},
		},
		{
			name: "ResolveAction - no entity",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.ResolveAction(ctx, "some_nwo", "some_gitref", 42, "some_job_id", 14)
				return r, err
			},
			wantReq: req{
				method: http.MethodGet,
				headers: http.Header{
					"User-Agent": []string{"launch-ghclient"},
				},
				url:  "/api/v3/repos/some_nwo/actions/resolve/some_gitref?jobId=some_job_id&workflowRepoId=14&workflowRunId=42",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    404,
				headers: make(http.Header),
				body:    `{"message":"Not Found"}`,
			},
			wantResp: (*ResolvedAction)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, err error) {
				want := &APIError{StatusCode: 404, ErrorMessage: "Unable to resolve action `some_nwo@some_gitref`, repository not found"}
				require.Equal(t, want, err)
			},
		},
		{
			name: "ResolveAction - rate limit exceeded (Forbidden)",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.ResolveAction(ctx, "some_nwo", "some_gitref", 42, "some_job_id", 14)
				return r, err
			},
			wantReq: req{
				method: http.MethodGet,
				headers: http.Header{
					"User-Agent": []string{"launch-ghclient"},
				},
				url:  "/api/v3/repos/some_nwo/actions/resolve/some_gitref?jobId=some_job_id&workflowRepoId=14&workflowRunId=42",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code: http.StatusForbidden,
				headers: http.Header{
					"X-RateLimit-Limit":     []string{"60"},
					"X-RateLimit-Remaining": []string{"0"},
				},
			},
			wantResp: (*ResolvedAction)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, err error) {
				want := &APIError{StatusCode: 403, ErrorMessage: "API rate limit exceeded while resolving action `some_nwo@some_gitref`."}
				require.Equal(t, want, err)
			},
		},
		{
			name: "ResolveAction - other 4xx error codes",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.ResolveAction(ctx, "some_nwo", "some_gitref", 42, "some_job_id", 14)
				return r, err
			},
			wantReq: req{
				method: http.MethodGet,
				headers: http.Header{
					"User-Agent": []string{"launch-ghclient"},
				},
				url:  "/api/v3/repos/some_nwo/actions/resolve/some_gitref?jobId=some_job_id&workflowRepoId=14&workflowRunId=42",
				body: ``,
			},
			wantReqCount: 1,
			sendResp: resp{
				code:    409,
				headers: make(http.Header),
				body:    `{"message":"unauthorized"}`,
			},
			wantResp: (*ResolvedAction)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, got error) {
				want := &APIError{StatusCode: 409, ErrorMessage: "unauthorized"}
				require.Equal(t, want, got)
			},
		},
		{
			name: "ResolveAction - other 5xx error codes",
			doRequest: func(cl Client) (any, error) {
				r, err := cl.ResolveAction(ctx, "some_nwo", "some_gitref", 42, "some_job_id", 14)
				return r, err
			},
			wantReq: req{
				method: http.MethodGet,
				headers: http.Header{
					"User-Agent": []string{"launch-ghclient"},
				},
				url:  "/api/v3/repos/some_nwo/actions/resolve/some_gitref?jobId=some_job_id&workflowRepoId=14&workflowRunId=42",
				body: ``,
			},
			wantReqCount: 4, // it should retry
			sendResp: resp{
				code:    503,
				headers: make(http.Header),
				body:    `{"message":"internal error"}`,
			},
			wantResp: (*ResolvedAction)(nil),
			checkErr: func(t *testing.T, srv *httptest.Server, got error) {
				want := &APIError{StatusCode: 503, ErrorMessage: "internal error"}
				require.Equal(t, want, got)
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// setup
			var (
				gotReq      req
				gotReqCount int
			)
			hdl := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				gotReqCount++
				body, err := io.ReadAll(r.Body)
				require.NoError(t, err)
				gotReq = req{
					method:  r.Method,
					headers: r.Header,
					url:     r.URL.String(),
					body:    string(body),
				}

				hdr := w.Header()
				for k, vals := range tt.sendResp.headers {
					for _, val := range vals {
						hdr.Add(k, val)
					}
				}
				w.WriteHeader(tt.sendResp.code)
				w.Write([]byte(tt.sendResp.body))
			})
			srv := httptest.NewServer(hdl)
			defer srv.Close()

			srvURL, err := url.Parse(srv.URL)
			require.NoError(t, err)

			client := makeClient(t, srvURL)

			// test
			gotResp, gotErr := tt.doRequest(client)

			// assert
			if tt.checkErr != nil {
				tt.checkErr(t, srv, gotErr)
			} else {
				require.NoError(t, gotErr)
			}
			require.Equal(t, tt.wantReq.method, gotReq.method)
			require.Equal(t, tt.wantReq.url, gotReq.url)
			// headers are a special case: some headers must merely exist, others need to have specific values
			for _, k := range headerKeys {
				require.Contains(t, gotReq.headers, k)
				delete(gotReq.headers, k) // remove it to avoid messing up the other assertions
			}
			require.Equal(t, tt.wantReq.headers, gotReq.headers)
			require.Equal(t, tt.wantReq.body, gotReq.body)
			require.Equal(t, tt.wantReqCount, gotReqCount)
			require.Equal(t, tt.wantResp, gotResp)
		})
	}
}

func checkErrMustBe(want error) func(t *testing.T, srv *httptest.Server, err error) {
	return func(t *testing.T, srv *httptest.Server, got error) {
		require.Equal(t, want, got)
	}
}

package launchserver

import (
	"context"
	"fmt"
	"io/ioutil"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/github/launch/observability"
	"github.com/github/launch/utils/ghtenant"
)

func Test_SetupGitHubTenantMiddleware(t *testing.T) {

	fakeObs := observability.NewTestObservability()

	tests := []struct {
		name                        string
		isMultiTenant               bool
		headers                     map[string]string
		exepectedStatusCode         int
		shouldTenantIDBeInContext   bool
		shouldTenantSlugBeInContext bool
	}{
		{
			name:                "not-multi-tenant",
			exepectedStatusCode: http.StatusOK,
		},
		{
			name:                      "multi-tenant/tenantID-only",
			isMultiTenant:             true,
			exepectedStatusCode:       http.StatusOK,
			headers:                   map[string]string{ghtenant.GitHubTenantIDHeader: "1"},
			shouldTenantIDBeInContext: true,
		},
		{
			name:                "multi-tenant/negative-tenantID-value",
			isMultiTenant:       true,
			headers:             map[string]string{ghtenant.GitHubTenantIDHeader: "-1"},
			exepectedStatusCode: http.StatusBadRequest,
		},
		{
			name:                "multi-tenant/missing-tenantID-header",
			isMultiTenant:       true,
			headers:             map[string]string{"foo": "bar"},
			exepectedStatusCode: http.StatusOK,
		},
		{
			name:                "multi-tenant/multiple-tenantID-values",
			isMultiTenant:       true,
			headers:             map[string]string{ghtenant.GitHubTenantIDHeader: "1,2"},
			exepectedStatusCode: http.StatusBadRequest,
		},
		{
			name:                "multi-tenant/tenantID-header-malformed",
			isMultiTenant:       true,
			headers:             map[string]string{ghtenant.GitHubTenantIDHeader: "boom"},
			exepectedStatusCode: http.StatusBadRequest,
		},
		{
			name:                        "multi-tenantslug",
			isMultiTenant:               true,
			exepectedStatusCode:         http.StatusOK,
			headers:                     map[string]string{ghtenant.GitHubTenantIDHeader: "1", ghtenant.GitHubTenantHeader: "staffship-01"},
			shouldTenantIDBeInContext:   true,
			shouldTenantSlugBeInContext: true,
		},
		{
			name:                "multi-tenantslug-emptyslug",
			isMultiTenant:       true,
			headers:             map[string]string{ghtenant.GitHubTenantIDHeader: "1", ghtenant.GitHubTenantHeader: ""},
			exepectedStatusCode: http.StatusBadRequest,
		},
		{
			name:                "multi-tenant/multiple-tenantslug-values",
			isMultiTenant:       true,
			headers:             map[string]string{ghtenant.GitHubTenantIDHeader: "1", ghtenant.GitHubTenantHeader: "staffship-01,staffship-02"},
			exepectedStatusCode: http.StatusBadRequest,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {

			// request handler stub to assert successful mw execution
			// it's expected that the middleware will stop execution and not invoke the request
			// handler if there's an error
			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if test.exepectedStatusCode != http.StatusOK {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte("expected error to stop processing, but request handler was called"))
				}

				// special case: some clients call twirp endpoints directly and will not have a tenant
				// header (e.g. actions-service) therefore, calling this will fail and cause a false positive
				tenantID, errTenantID := ghtenant.TenantIDFromContext(r.Context(), test.isMultiTenant)
				tenantSlug, errTenantSlug := ghtenant.TenantSlugFromContext(r.Context(), test.isMultiTenant)

				if errTenantID != nil && !(test.isMultiTenant && !test.shouldTenantIDBeInContext) {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("error asserting tenant id context in stub handler: %v", errTenantID)))
					return
				}

				if test.shouldTenantIDBeInContext && tenantID != int64(1) {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("expected github tenant id  to be '1', but got '%v'", tenantID)))
					return
				}

				if !test.shouldTenantIDBeInContext && tenantID != 0 {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("expected github tenant id to be '0', but got '%v'", tenantID)))
					return
				}

				if errTenantSlug != nil && !(test.isMultiTenant && !test.shouldTenantSlugBeInContext) {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("error asserting tenant slug context in stub handler: %v", errTenantSlug)))
					return
				}

				if test.shouldTenantSlugBeInContext && tenantSlug != "staffship-01" {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("expected github tenant slug to be 'staffship-01', but got '%v'", tenantSlug)))
					return
				}

				if !test.shouldTenantSlugBeInContext && tenantSlug != "" {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("expected github tenant to be '', but got '%v'", tenantSlug)))
					return
				}

				if test.shouldTenantSlugBeInContext && test.shouldTenantIDBeInContext && tenantID != int64(1) && tenantSlug != "staffship-01" {
					w.WriteHeader(http.StatusInternalServerError)
					w.Write([]byte(fmt.Sprintf("expected github tenant to be '', but got '%v'", tenantSlug)))
					return
				}

				w.WriteHeader(http.StatusOK)
				w.Write([]byte("all checks in test handler passed"))
			})

			req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, "/", nil)
			if err != nil {
				t.Fatalf("error creating request: %v", err)
			}

			for k, v := range test.headers {
				vals := strings.Split(v, ",")

				for _, val := range vals {
					req.Header.Add(k, val)
				}
			}

			resRec := httptest.NewRecorder()

			mw := SetupGitHubTenantMiddleware(test.isMultiTenant, fakeObs)
			testMW := (mw(handler))

			testMW.ServeHTTP(resRec, req)

			res := resRec.Result()
			if test.exepectedStatusCode != res.StatusCode {
				b, _ := ioutil.ReadAll(res.Body)
				defer res.Body.Close()
				t.Fatalf("expected status code '%d', but got '%d', msg: %v", test.exepectedStatusCode, res.StatusCode, string(b))
			}
		})
	}
}

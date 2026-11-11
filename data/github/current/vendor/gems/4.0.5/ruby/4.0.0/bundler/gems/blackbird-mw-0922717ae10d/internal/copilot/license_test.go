package copilot

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_GetsLicense(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	req.Header.Add(gitHubCopilotLicenseHeader, "copilot_enterprise_seat")

	assertHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l := GetLicense(r.Context())
		require.Equal(t, "copilot_enterprise_seat", l.Sku)
		require.True(t, l.HasLimitedAccess)
	})
	w := httptest.NewRecorder()
	LicenseHandler(assertHandler).ServeHTTP(w, req)
}

func Test_NoHeader(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)

	assertHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l := GetLicense(r.Context())
		require.Nil(t, l)
	})
	w := httptest.NewRecorder()
	LicenseHandler(assertHandler).ServeHTTP(w, req)
}

func Test_GetsLicenseWithLimitedAccess(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	req.Header.Add(gitHubCopilotLicenseHeader, "copilot_enterprise_seat")
	req.Header.Add(gitHubCopilotHasLimitedAccessHeader, "true")

	assertHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l := GetLicense(r.Context())
		require.Equal(t, "copilot_enterprise_seat", l.Sku)
		require.True(t, l.HasLimitedAccess)
	})
	w := httptest.NewRecorder()
	LicenseHandler(assertHandler).ServeHTTP(w, req)
}

func Test_GetsLicenseWithoutLimitedAccess(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/", http.NoBody)
	req.Header.Add(gitHubCopilotLicenseHeader, "copilot_enterprise_seat")
	req.Header.Add(gitHubCopilotHasLimitedAccessHeader, "false")

	assertHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		l := GetLicense(r.Context())
		require.Equal(t, "copilot_enterprise_seat", l.Sku)
		require.False(t, l.HasLimitedAccess)
	})
	w := httptest.NewRecorder()
	LicenseHandler(assertHandler).ServeHTTP(w, req)
}

package copilot

import (
	"context"
	"net/http"
)

const (
	gitHubCopilotLicenseHeader          = "X-GitHub-Copilot-License"
	gitHubCopilotHasLimitedAccessHeader = "X-GitHub-Copilot-Has-Limited-Access"
)

type License struct {
	Sku              string
	HasLimitedAccess bool
}

// LicenseHandler is a middleware that reads copilot license data from the request headers and inserts this information
// into the request context.
func LicenseHandler(next http.Handler) http.Handler {
	fn := func(w http.ResponseWriter, r *http.Request) {
		sku := r.Header.Get(gitHubCopilotLicenseHeader)
		if sku != "" {
			r = r.WithContext(withLicense(r.Context(), &License{
				Sku:              sku,
				HasLimitedAccess: r.Header.Get(gitHubCopilotHasLimitedAccessHeader) != "false",
			}))
		}

		next.ServeHTTP(w, r)
	}
	return http.HandlerFunc(fn)
}

// GetLicense returns the Copilot license if one is present.
func GetLicense(ctx context.Context) *License {
	if ctx == nil {
		return nil
	}
	v, ok := ctx.Value(ctxCopilotLicenseKey{}).(*License)
	if !ok {
		return nil
	}
	return v
}

func withLicense(ctx context.Context, l *License) context.Context {
	return context.WithValue(ctx, ctxCopilotLicenseKey{}, l)
}

type ctxCopilotLicenseKey struct{}

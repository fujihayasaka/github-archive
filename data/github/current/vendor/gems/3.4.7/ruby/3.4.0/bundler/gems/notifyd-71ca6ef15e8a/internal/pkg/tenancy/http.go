package tenancy

import (
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

// Tenant headers
const (
	HeaderTenantSlug = "X-GitHub-Tenant"
	HeaderTenantID   = "X-GitHub-Tenant-ID"
)

// Headers is compatible with http.Header.Get
type Headers interface {
	Get(string) string
}

type mapHeaders struct {
	// http.Header already canonalizes header names, so we can use
	// it here to ensure names are always transformed properly
	headers http.Header
}

func newMapHeaders(headers map[string]string) mapHeaders {
	h := http.Header{}
	for name, value := range headers {
		h.Add(name, value)
	}

	return mapHeaders{headers: h}
}

func (h mapHeaders) Get(name string) string {
	return h.headers.Get(name)
}

// IntoHeadersMap returns a map of headers containing the tenant information
func IntoHeadersMap(tenant Tenant) map[string]string {
	return map[string]string{
		HeaderTenantSlug: tenant.Slug(),
		HeaderTenantID:   fmt.Sprintf("%d", tenant.ID()),
	}
}

// Inject injects the tenant information into the given headers map.
func Inject(tenant Tenant, headers map[string]string) {
	headers[HeaderTenantSlug] = tenant.Slug()
	headers[HeaderTenantID] = fmt.Sprintf("%d", tenant.ID())
}

// UpdateFromMap updates a given tenant with information found in the given map
func UpdateFromMap(tenant Tenant, headers map[string]string) (Tenant, error) {
	return UpdateFromHeaders(tenant, newMapHeaders(headers))
}

// UpdateFromHeaders updates a given tenant with information found in the given Headers
// This method will update the tenant with any field found.
// It will return an error along with the updated tenant with any missing field.
func UpdateFromHeaders(tenant Tenant, headers Headers) (Tenant, error) {
	errs := []string{}
	if slug := headers.Get(HeaderTenantSlug); slug != "" {
		tenant = tenant.WithSlug(slug)
	} else {
		errs = append(errs, "No tenant Slug found in headers")
	}

	if sid := headers.Get(HeaderTenantID); sid != "" {
		if id, err := strconv.ParseInt(sid, 10, 64); err == nil {
			tenant = tenant.WithID(id)
		} else {
			errs = append(errs, fmt.Sprintf("Found malformed tenant ID in headers, it should be a number: %s", sid))
		}
	} else {
		errs = append(errs, "No tenant ID found in headers")
	}

	if len(errs) > 0 {
		return tenant, errors.New(strings.Join(errs, ". "))
	}

	return tenant, nil
}

// HTTPClient is the minimum interface necessary to make types compatible with a subset of http.Client
type HTTPClient interface {
	Do(*http.Request) (*http.Response, error)
}

// forwarder sets tenant information into the outgoing HTTP Request headers
// NOTE: The tenant is extracted from the request's context
type forwarder struct {
	next HTTPClient
}

// NewForwarder creates a new forwarder
func NewForwarder(next HTTPClient) HTTPClient {
	return forwarder{next: next}
}

// Do updates the http.Request's header with the current Tenant information.
// The Tenant is extracted from the http.Request's Context, and if is not
// present this method will return an error.
func (fwd forwarder) Do(req *http.Request) (*http.Response, error) {
	tenant, err := FromContext(req.Context())
	if err != nil {
		return nil, err
	}

	headers := IntoHeadersMap(tenant)
	for name, value := range headers {
		req.Header.Set(name, value)
	}

	return fwd.next.Do(req)
}

package ghtenant

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/utils/twirputils"
)

const (
	// GitHubTenantHeader is a request header containing tenant information
	// for incoming requests the value will be the tenant slug. When used in
	// outgoing calls the value of the header can either have a value of
	// id=:tenantID or sc=:tenantShortCode or just slug value.
	// Launch uses this header in API calls to the monolith (and other services) when NWOs are used instead of unique ids.
	GitHubTenantHeader = "X-GitHub-Tenant"
	// GitHubTenantIDHeader is a request header containing the tenant id. This header
	// is sent by clients and in webhook payloads
	GitHubTenantIDHeader = "X-GitHub-Tenant-ID"
	// SerializeLoginHeader is a request header containing a string value of either
	// 'display' or 'unique' indicating to the monolith whether logins returned by API
	// calls should be unsuffixed or suffixed respectively.
	SerializeLoginHeader  = "X-Serialize-Login"
	SerializeLoginUnique  = "unique"
	SerializeLoginDisplay = "display"
)

type ghtenantIDCtxKey struct{}
type ghtenantSlugCtxKey struct{}

// GitHubTenant represents a GitHub EMU Business in a multi-tenant environment
type GitHubTenant struct {
	ID   int64  `json:"id"`
	Slug string `json:"slug"`
}

func (t GitHubTenant) Validate(isMultiTenant bool) error {
	if !isMultiTenant {
		if t.ID != 0 || t.Slug != "" {
			return errors.New("GitHub tenant should only be set in multi-tenant environments")
		}

		return nil
	}

	_, err := ValidateTenantID(t.ID)
	if err != nil {
		return err
	}

	_, err = ValidateTenantSlug(t.Slug)
	if err != nil {
		return err
	}

	return nil
}

func GitHubTenantFromContext(ctx context.Context, isMultiTenant bool) (GitHubTenant, error) {
	if !isMultiTenant {
		return GitHubTenant{}, nil
	}

	tenantID, err := TenantIDFromContext(ctx, isMultiTenant)
	if err != nil {
		return GitHubTenant{}, err
	}

	tenantSlug, err := TenantSlugFromContext(ctx, isMultiTenant)
	if err != nil {
		return GitHubTenant{}, err
	}

	return GitHubTenant{
		ID:   tenantID,
		Slug: tenantSlug,
	}, nil
}

// TenantSlugFromRequest returns the tenant slug from a context. A no-op is
// performed if the service is not running in multi-tenant mode. An error is returned
// in the following cases:
// - The service is running in multi-tenant mode, but tenant slug is not found in the context
// - The service is running in multi-tenant mode, but the tenant slug is not a string
func TenantSlugFromContext(ctx context.Context, isMultiTenant bool) (string, error) {
	if !isMultiTenant {
		return "", nil
	}

	tenantSlugVal := ctx.Value(ghtenantSlugCtxKey{})
	if tenantSlugVal == nil {
		return "", errors.New("github tenant slug not found in context")
	}

	tenantSlug, err := ValidateTenantSlug(tenantSlugVal)
	if err != nil {
		return "", err
	}

	return tenantSlug, nil
}

// TenantIDFromContext returns the tenant ID from the context. An error is
// returned in the following cases:
// - The service is running in multi-tenant mode, but tenant id is not found in the context
// - The service is running in multi-tenant mode, but the tenant id is not an int
//
// If the sevice is not running in multi-tenant mode, this function will always return 0,nil
func TenantIDFromContext(ctx context.Context, isMultiTenant bool) (int64, error) {
	if !isMultiTenant {
		return 0, nil
	}

	tenantVal := ctx.Value(ghtenantIDCtxKey{})
	if tenantVal == nil {
		return 0, errors.New("github tenant id not found in context")
	}

	tenantID, err := ValidateTenantID(tenantVal)
	if err != nil {
		return 0, err
	}

	return tenantID, nil
}

// ContextWithTenantID returns a new context with the github tenant ID set.
// If the service is not running in multi-tenant mode, this function will preform a no-op, returning the context given.
func ContextWithTenantID(ctx context.Context, tenantID int64, isMultiTenant bool) (context.Context, error) {
	if !isMultiTenant {
		return ctx, nil
	}

	if _, err := ValidateTenantID(tenantID); err != nil {
		return ctx, err
	}

	return context.WithValue(ctx, ghtenantIDCtxKey{}, tenantID), nil
}

// ContextWithTenantSlug returns a new context with the github tenant header set.
// If the service is not running in multi-tenant mode, this function will preform a no-op, returning the context given.
func ContextWithTenantSlug(ctx context.Context, tenant string, isMultiTenant bool) (context.Context, error) {
	if !isMultiTenant {
		return ctx, nil
	}

	if _, err := ValidateTenantSlug(tenant); err != nil {
		return ctx, err
	}

	return context.WithValue(ctx, ghtenantSlugCtxKey{}, tenant), nil
}

// ForwardGitHubTenant finds the tenant id and tenant slug from the context and adds it to the request headers
// with tenant id under X-GitHub-Tenant-ID and tenant slug under X-GitHub-Tenant (slug is best effort).
func ForwardGitHubTenant(r *http.Request, isMultiTenant bool, logger logger.Logger) error {
	if !isMultiTenant {
		return nil
	}

	ctx := r.Context()

	tenantHeaders, err := getTenantHeaders(ctx, isMultiTenant, logger)
	if err != nil {
		return err
	}

	for k, v := range tenantHeaders {
		r.Header.Set(k, v)
	}

	return nil
}

// ContextWithTwirpTenantHeaders returns a new context that includes both tenant ID under X-GitHub-Tenant-ID
// and tenant slug headers under X-GitHub-Tenant (slug is best effort). All Twirp requests made using the returned
// context will include the GitHub tenant header(s).
// If the service is not running in multi-tenant mode, this function will perform a no-op.
func ContextWithTwirpTenantHeaders(ctx context.Context, isMultiTenant bool, logger logger.Logger) (context.Context, error) {
	if !isMultiTenant {
		return ctx, nil
	}

	tenantHeaders, err := getTenantHeaders(ctx, true, logger)
	if err != nil {
		return ctx, err
	}

	for k, v := range tenantHeaders {
		ctx, err = twirputils.ContextWithTwirpHeader(ctx, k, v)
		if err != nil {
			return ctx, err
		}
	}

	return ctx, nil
}

// getTenantHeaders finds the tenant id and tenant slug from the context and set
// X-GitHub-Tenant-ID to tenant id and
// X-GitHub-Tenant to tenant slug if slug exist, otherwise set it to id=:tenantID
// If the service is not running in multi-tenant mode, this function will return an empty map
func getTenantHeaders(ctx context.Context, isMultiTenant bool, logger logger.Logger) (map[string]string, error) {
	headers := make(map[string]string)
	if !isMultiTenant {
		return headers, nil
	}

	ghTenantID, tenantIDErr := TenantIDFromContext(ctx, isMultiTenant)
	if tenantIDErr != nil {
		// throw error if tenant id does not exist in context
		return nil, tenantIDErr
	}
	headers[GitHubTenantIDHeader] = strconv.FormatInt(ghTenantID, 10)

	ghTenantSlug, tenantSlugErr := TenantSlugFromContext(ctx, isMultiTenant)
	if tenantSlugErr != nil {
		// this is best effort, continue to send tennat id over if slug is missing
		logger.Error(ctx, "failed to get tenant slug from context", kvp.Err(tenantSlugErr))
		headers[GitHubTenantHeader] = fmt.Sprintf("id=%s", strconv.FormatInt(ghTenantID, 10))

	} else {
		headers[GitHubTenantHeader] = ghTenantSlug
	}

	return headers, nil
}

// ContextWithSerializeTenantHeader returns a new context that includes the X-Serialize-Login header as a Twirp header set
// to the given serializer mode. All Twirp requests made using the returned context will include the X-Serialize-Login header.
// An error is returned if the given serialize mode is invalid.
//
// If the service is not running in multi-tenant mode, this function will perform a no-op, returning the context given.
func ContextWithSerializeLoginHeader(ctx context.Context, serializeMode string, isMultiTenant bool) (context.Context, error) {
	if !isMultiTenant {
		return ctx, nil
	}

	if serializeMode != SerializeLoginDisplay && serializeMode != SerializeLoginUnique {
		return ctx, errors.New("invalid serialize mode")
	}

	return twirputils.ContextWithTwirpHeader(ctx, SerializeLoginHeader, serializeMode)
}

func ValidateTenantID(tenantID any) (int64, error) {
	switch v := tenantID.(type) {
	case int64:
		if v <= 0 {
			return 0, errors.New("github tenant id should be greater than 0")
		}

		return v, nil
	case string:
		tenantIDInt, err := strconv.ParseInt(v, 10, 64)
		if err != nil {
			return 0, errors.New("github tenant id should be parsable to int64")
		}

		if tenantIDInt <= 0 {
			return 0, errors.New("github tenant id should be greater than 0")
		}

		return tenantIDInt, nil
	default:
		return 0, errors.New("github tenant id should be either int64 or string")
	}
}

func ValidateTenantSlug(slug any) (string, error) {
	switch v := slug.(type) {
	case string:
		if v == "" {
			return "", errors.New("github tenant slug should not be empty")
		}

		return v, nil
	default:
		return "", errors.New("github tenant slug should be string")
	}
}

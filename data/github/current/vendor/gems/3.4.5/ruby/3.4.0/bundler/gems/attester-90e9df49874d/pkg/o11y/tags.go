package o11y

type ctxTenantIDKey string

const (
	TenantIDCtxKeyName ctxTenantIDKey = "ctx-tenant-request-id"

	GitHubRequestIDLabel string = "gh.request_id"
	ErrTypeLabel         string = "http.request.error_type"
)

package o11y

type ctxTenantIDKey string
type ctxNpmRequestIDKey string

const (
	NpmCtxKeyName      ctxNpmRequestIDKey = "ctx-npm-request-id"
	TenantIDCtxKeyName ctxTenantIDKey     = "ctx-tenant-request-id"

	NpmRequestIDLabel    string = "npm.request_id"
	GitHubRequestIDLabel string = "gh.request_id"
	ErrTypeLabel         string = "http.request.error_type"

	NpmRequestID string = "X-npm-request-id"
)

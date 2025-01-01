package job

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

func Test_Headers_WithDefaultSenderHeaders(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()

	ctx = o11y.CtxSetRequestID(ctx)

	headers := NewHeaders(WithDefaultSenderHeaders(ctx))
	asMap := headers.IntoMap()

	r.Equal(o11y.CtxGetRequestID(ctx), asMap["gh-request-id"])
	r.Equal("notifyd", asMap["notifyd-message-producer"])
	r.Equal("aqueduct", asMap["notifyd-message-published-to"])
}

func Test_Headers_WithHeadersFromMap(t *testing.T) {
	r := require.New(t)
	original := map[string]string{
		"traceparent": "abcde",
		"ot-spanid":   "1234",
	}
	headers := NewHeaders(WithHeadersFromMap(original))

	r.Equal(original, headers.IntoMap())
}

func Test_Headers_WithContentLengthHeader(t *testing.T) {
	r := require.New(t)
	headers := NewHeaders(WithContentLengthHeader(1024))

	r.Equal("1024", headers.IntoMap()["content-length"])
}

func Test_Headers_WithTenantHeaders(t *testing.T) {
	r := require.New(t)

	var tenant tenancy.Tenant
	tenant = tenancy.NewMultiTenant()
	tenant = tenant.WithSlug("avocado")
	tenant = tenant.WithID(123)

	headers := NewHeaders(WithTenantHeaders(tenant))

	h := headers.IntoMap()
	r.Equal("avocado", h["X-GitHub-Tenant"])
	r.Equal("123", h["X-GitHub-Tenant-ID"])
}

func Test_Headers_GetSet(t *testing.T) {
	headers := NewHeaders()

	t.Run("sets a header", func(tt *testing.T) {
		r := require.New(tt)
		headers.Set(HeaderContentEncoding, "deflate")

		value, ok := headers.Get(HeaderContentEncoding)
		r.True(ok)
		r.Equal("deflate", value)
		r.Equal("deflate", headers.IntoMap()["content-encoding"])
	})

	t.Run("does not return an unset header", func(tt *testing.T) {
		r := require.New(tt)
		_, nope := headers.Get(HeaderProducer)
		r.False(nope)
	})

	t.Run("does not set an empty header", func(tt *testing.T) {
		r := require.New(tt)
		headers.Set(HeaderPublishedTo, "")
		_, nope := headers.Get(HeaderPublishedTo)
		r.False(nope)
	})

	t.Run("normalizes names", func(tt *testing.T) {
		r := require.New(tt)
		headers.SetRaw("Content-ENCODING", "deflate")

		value, ok := headers.Get(HeaderContentEncoding)
		r.True(ok)
		r.Equal("deflate", value)
	})
}

func Test_Headers_ToLog(t *testing.T) {
	r := require.New(t)
	headers := NewHeaders()
	headers.Set("some-key", "some-value")
	fields := headers.ToLog()
	r.Len(fields, 1)
	r.Equal(kvp.String("gh.aqueduct.job.header.some_key", "some-value"), fields[0])
}

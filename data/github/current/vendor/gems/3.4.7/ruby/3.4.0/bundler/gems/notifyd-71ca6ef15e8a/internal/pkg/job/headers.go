package job

import (
	"context"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Header represents a header
type Header string

// Set of predefined header names
const (
	// GitHub's Request ID
	HeaderRequestID Header = "gh-request-id"
	// Where this message was sent in the first place
	HeaderPublishedTo Header = "notifyd-message-published-to"
	// Who is sending the message
	HeaderProducer Header = "notifyd-message-producer"
	// HTTP-like headers
	HeaderContentLength   Header = "content-length" // in bytes
	HeaderContentEncoding Header = "content-encoding"
)

const defaultProducer = "notifyd"
const aqueductSystem = "aqueduct"
const hydroSystem = "hydro"

// normalize transforms header names from X-Header into x_header
// This ensures that we don't miss headers that have case inconsistencies
func normalize(original string) string {
	return strings.ToLower(strings.ReplaceAll(original, "-", "_"))
}

// Field represents a header field
type Field struct {
	name  string // original field name
	value string
}

// Headers describe the set of headers of a request
// They keys are the header names normalized
type Headers struct {
	raw map[string]Field
}

// HeaderOption is a function that sets a header
type HeaderOption func(headers *Headers)

// Set sets a header
func (h *Headers) Set(key Header, value string) {
	h.SetRaw(string(key), value)
}

// SetRaw sets a header
func (h *Headers) SetRaw(key, value string) {
	// Do not save empty values
	if value != "" {
		h.raw[normalize(key)] = Field{name: key, value: value}
	}
}

// Get returns a header
func (h *Headers) Get(key Header) (string, bool) {
	return h.GetRaw(string(key))
}

// GetRaw returns a header
func (h *Headers) GetRaw(key string) (string, bool) {
	if field, ok := h.raw[normalize(key)]; ok {
		return field.value, true
	}

	return "", false
}

// IntoMap returns a copy of the headers as a map
func (h *Headers) IntoMap() map[string]string {
	m := make(map[string]string, len(h.raw))
	for _, field := range h.raw {
		m[field.name] = field.value
	}

	return m
}

// ToLog returns the headers as a list of key-value pairs
func (h *Headers) ToLog() []kvp.Field {
	fields := make([]kvp.Field, 0, len(h.raw))

	for header, field := range h.raw {
		name := fmt.Sprintf("gh.aqueduct.job.header.%s", header)
		fields = append(fields, kvp.String(name, field.value))
	}

	return fields
}

/*
NewHeaders builds a new set of Headers.
Use it with any With* builder option to set up default keys

Example:

headers := job.NewHeaders(

	job.WithPublishedToAqueductHeader(),
	job.WithProducerHeader("my-producer"),
	job.WithContentLengthHeader(len(payload)),

)

// New header values can be set later too
headers.Set(job.HeaderRequestID, "abc")
*/
func NewHeaders(options ...HeaderOption) *Headers {
	raw := make(map[string]Field, 10)
	headers := &Headers{raw}

	for _, opt := range options {
		opt(headers)
	}

	return headers
}

// WithRequestIDHeader sets the request ID header
var WithRequestIDHeader = buildHeaderOption(HeaderRequestID)

// WithPublishedToHeader sets the published-to header
var WithPublishedToHeader = buildHeaderOption(HeaderPublishedTo)

// WithProducerHeader sets the producer header
var WithProducerHeader = buildHeaderOption(HeaderProducer)

// WithContentEncodingHeader sets the content-encoding header
var WithContentEncodingHeader = buildHeaderOption(HeaderContentEncoding)

// Helper function to build basic HeaderOption builders
func buildHeaderOption(key Header) func(string) HeaderOption {
	return func(value string) HeaderOption {
		return func(headers *Headers) {
			headers.Set(key, value)
		}
	}
}

// WithContentLengthHeader sets the content-length header
func WithContentLengthHeader(value int) HeaderOption {
	return func(headers *Headers) {
		headers.Set(HeaderContentLength, fmt.Sprintf("%d", value))
	}
}

// WithDefaultProducerHeader sets the default producer header
func WithDefaultProducerHeader() HeaderOption {
	return WithProducerHeader(defaultProducer)
}

// WithPublishedToAqueductHeader sets the published-to header to aqueduct
func WithPublishedToAqueductHeader() HeaderOption {
	return WithPublishedToHeader(aqueductSystem)
}

// WithPublishedToHydroHeader sets the published-to header to hydro
func WithPublishedToHydroHeader() HeaderOption {
	return WithPublishedToHeader(hydroSystem)
}

// WithHeadersFromMap extracts headers from a map
// NOTE: This does not validate header names
func WithHeadersFromMap(raw map[string]string) HeaderOption {
	return func(headers *Headers) {
		for key, value := range raw {
			headers.SetRaw(key, value)
		}
	}
}

// WithHeadersFromCtx extracts relevant information from the context
// and sets it with the proper header names
func WithHeadersFromCtx(ctx context.Context) HeaderOption {
	requestID := o11y.CtxGetRequestID(ctx)

	return WithRequestIDHeader(requestID)
}

// WithDefaultSenderHeaders is a HeaderOption builder that sets the following headers:
//   - published-to to aqueduct
//   - producer to aqueduct
//   - extracts headers from the context
func WithDefaultSenderHeaders(ctx context.Context) HeaderOption {
	options := []HeaderOption{
		WithPublishedToAqueductHeader(),
		WithDefaultProducerHeader(),
		WithHeadersFromCtx(ctx),
	}

	return func(headers *Headers) {
		for _, opt := range options {
			opt(headers)
		}
	}
}

// WithTenantHeaders extracts the Tenant information and sets the headers used to propagate
// it across services. These headers are only set in multi-tenant environments.
func WithTenantHeaders(tenant tenancy.Tenant) HeaderOption {
	if tenant.IsMultiTenant() {
		return WithHeadersFromMap(tenancy.IntoHeadersMap(tenant))
	}

	return func(_ *Headers) {}
}

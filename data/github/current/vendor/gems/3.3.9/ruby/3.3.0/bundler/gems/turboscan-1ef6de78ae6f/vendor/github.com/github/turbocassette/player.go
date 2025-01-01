package turbocassette

import (
	"context"
	"net/http"
	"net/textproto"
	"os"
	"regexp"

	"github.com/github/turbocassette/vcr"
)

// A Player encapsulate all required operations for playing and recording a cassette
type Player struct {
	// handler is the HTTP Handler against which the requests will be replayed.
	handler http.Handler
	// host is the host:port for the given HTTP Handler.
	// If set, only interactions matching the host will be considered.
	host *string
	// A filter to apply to the response object. The response is represented as a string.
	rawResponseFilter []func(body string) string
	// ignoreRequestHeaders contains the set of Headers to ignore if they appear in the Request
	// This make it simpler to keep requests consistent, and ensures that behavior
	// does not depend on these parameters.
	// Use IgnoreRequestHeader to ensure that the value is normalized correctly
	ignoreRequestHeaders normHeaders
}

func NewPlayer(h http.Handler, opts ...PlayerOption) *Player {
	p := &Player{
		handler: h,
	}
	for _, opt := range opts {
		opt(p)
	}
	return p
}

type PlayerOption func(*Player)

func WithResponseFilter(f func(body string) string) PlayerOption {
	return func(p *Player) {
		p.rawResponseFilter = append(p.rawResponseFilter, f)
	}
}

func WithHost(h string) PlayerOption {
	return func(p *Player) {
		p.host = &h
	}
}

func WithIgnoreRequestHeaders(hs ...string) PlayerOption {
	return func(p *Player) {
		for _, h := range hs {
			p.ignoreRequestHeader(h)
		}
	}
}

// TimestampsFilter replaces all timestamps with 0001-01-01T00:00:00Z
func TimestampsFilter(body string) string {
	return timestampPattern.ReplaceAllLiteralString(body, "0001-01-01T00:00:00Z")
}

// UUIDsFilter replaces all v4 UUIDs to 11111111-2222-3333-4444-000000000000
// Only v4 UUIDS are replaced, so GUID that are not v4 are kept unchanged.
func UUIDsFilter(body string) string {
	return uuidPattern.ReplaceAllLiteralString(body, "11111111-2222-3333-4444-000000000000")
}

// timestampPattern will match a RFC3339 timestamp
var timestampPattern = regexp.MustCompile(`([0-9]+)-(0[1-9]|1[012])-(0[1-9]|[12][0-9]|3[01])[Tt]([01][0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9]|60)([.][0-9]+)?(([Zz])|([+|-]([01][0-9]|2[0-3]):[0-5][0-9]))`)

// uuidPattern will match a hex representation of a v4 uuid/guid
var uuidPattern = regexp.MustCompile(`[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[0-9a-f]{4}-[0-9a-f]{12}`)

// normHeaders is the set of normalized HTT Headers.
type normHeaders = map[string]struct{}

func (p *Player) ignoreRequestHeader(h string) {
	if p.ignoreRequestHeaders == nil {
		p.ignoreRequestHeaders = make(map[string]struct{})
	}
	p.ignoreRequestHeaders[textproto.CanonicalMIMEHeaderKey(h)] = struct{}{}
}

// Replay executes the VCR against the http.Handler.
// If overwrite is true, and the output is different, the VCR file will be updated.
func (p *Player) Replay(ctx context.Context, vcrFile *os.File, overwrite bool) error {
	if overwrite {
		return overwriteTape(ctx, vcrFile, p.replay)
	}

	// If overwrite is not set, then operations should not affect the VCR file.
	// We enforce this by opening the VCR file here and passing directly the
	// tape object below.
	tape, err := vcr.Open(vcrFile)
	if err != nil {
		return err
	}
	return diffTape(ctx, tape, p.replay)
}

func (p *Player) replay(ctx context.Context, tape *vcr.Cassette) error {
	return replay(ctx, p, tape)
}

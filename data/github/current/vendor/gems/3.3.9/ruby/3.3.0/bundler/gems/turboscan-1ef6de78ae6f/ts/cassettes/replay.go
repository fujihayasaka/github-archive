package cassettes

import (
	"flag"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"testing"

	"github.com/pkg/errors"

	tc "github.com/github/turbocassette"

	"github.com/stretchr/testify/require"
)

var overwrite = flag.Bool("overwrite", false, "Overwrite existing cassettes")

func rootDir() string {
	_, file, _, _ := runtime.Caller(0)

	return filepath.Clean(filepath.Join(filepath.Dir(file), "../..")) + "/"
}

// Rewrite all CodeQL query URIs so that the commit hash does not trigger a recording
func queryURIFilter(body string) string {
	queryURIPattern := regexp.MustCompile(`"https://github\.com/github/codeql/blob/[0-9a-f]{40}/`)
	return queryURIPattern.ReplaceAllLiteralString(body, `"https://github.com/github/codeql/blob/0000000000000000000000000000000000000000/`)
}

func newPlayer(h http.Handler) *tc.Player {
	p := tc.NewPlayer(
		h,
		tc.WithResponseFilter(tc.TimestampsFilter),
		tc.WithResponseFilter(tc.UUIDsFilter),
		tc.WithResponseFilter(queryURIFilter),
		tc.WithHost("localhost:8888"),
		tc.WithIgnoreRequestHeaders("Request-HMAC", "User-Agent", "X-GLB-Via", "X-GitHub-Request-Id"),
		tc.WithIgnoreRequestHeaders("ot-tracer-sampled", "ot-tracer-spanid", "ot-tracer-traceid", "Traceparent"),
	)

	return p
}

// ReplayReadOnly will replay a cassette to check for differences,
// but will never overwrite the cassette, even if the UPDATE_CASSETTES environment variable is true.
// This is helpful for cassettes that are used in different tests.
// Usually only one of the tests should be allowed to modify the cassette.
func (session *Session) ReplayReadOnly(t *testing.T, name string) {
	t.Helper()

	// Save overwrite state
	saved := *overwrite
	*overwrite = false
	defer func() {
		// Restore overwrite state
		*overwrite = saved
	}()
	session.Replay(t, name)
}

// Replay will replay a cassette to check for differences,
// overwriting it if the UPDATE_CASSETTES environment variable is true
func (session *Session) Replay(t *testing.T, name string) {
	t.Helper()

	vcrFile, err := os.Open(filepath.Join(rootDir(), "ruby/spec/fixtures/vcr_cassettes", name))
	require.NoError(t, err)
	t.Cleanup(func() {
		require.NoError(t, vcrFile.Close())
	})

	player := newPlayer(session.handler)

	err = player.Replay(session.ctx, vcrFile, *overwrite)
	if errors.Is(err, tc.CassetteChanged) {
		err = errors.Errorf("cassette has changed: run `make cassettes` and commit the result if this change looks legitimate:\n%s", err)
	}

	require.NoError(t, err, "failed to record %v", name)
}

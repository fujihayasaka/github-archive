//go:generate go test -v ./... -overwrite
package api_test

import (
	"bytes"
	"context"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"slices"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/github/turboghas/internal/fromctx"
	"github.com/simon-engledew/go-vcr"
	"github.com/stretchr/testify/require"
)

var root = func() string {
	_, file, _, _ := runtime.Caller(0)

	return filepath.Clean(filepath.Join(filepath.Dir(file), "../.."))
}()

func findCaller(t *testing.T, pred func(frame runtime.Frame) bool, depth int) runtime.Frame {
	t.Helper()
	rpc := make([]uintptr, depth)
	size := runtime.Callers(0, rpc)
	more := size > 0
	iter := runtime.CallersFrames(rpc)
	var frame runtime.Frame
	for {
		require.True(t, more)
		frame, more = iter.Next()

		rel, err := filepath.Rel(root, frame.File)
		require.NoError(t, err)

		if strings.HasPrefix(rel, "../") {
			continue
		}

		frame.File = rel

		if pred(frame) {
			return frame
		}
	}
}

func isApiCall(frame runtime.Frame) bool {
	base := filepath.Base(frame.File)

	return strings.HasPrefix(frame.File, "internal/api/") && base != "api.go" && !strings.HasSuffix(base, "_test.go")
}

func replay(t *testing.T, name string, handler http.Handler, opts ...vcr.NormalizeOption) {
	t.Helper()

	queries := map[string][]string{}
	var mutex sync.Mutex

	noisePattern := regexp.MustCompile(`(?m)(?:/*\* internal/api/\S+.go:\d+ \*/ |^\s+/*\* internal/api/\S+.go:\d+ \*/\s+$\n|\s+$)`)

	reporter := func(ctx context.Context) func(query string, duration time.Duration, results int64) {
		return func(query string, duration time.Duration, results int64) {
			frame := findCaller(t, isApiCall, 10)
			t.Logf("\n%s:%d:\n%s", frame.File, frame.Line, query)

			dir := filepath.Dir(frame.File)

			out := filepath.Join(root, dir, "queries", t.Name()+".sql")

			mutex.Lock()
			queries[out] = append(queries[out], strings.TrimSpace(noisePattern.ReplaceAllString(query, "")))
			mutex.Unlock()
		}
	}

	t.Cleanup(func() {
		for path, examples := range queries {
			sort.Strings(examples)

			next := []byte(strings.Join(slices.Compact(examples), "\n\n--\n\n") + "\n")

			prev, err := os.ReadFile(path)
			if err == nil && bytes.Equal(prev, next) {
				return
			}

			require.NoError(t, os.WriteFile(path, next, 0o644))
		}
	})

	next := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		handler.ServeHTTP(w, r.WithContext(fromctx.QueryReporter.With(r.Context(), reporter)))
	})

	vcr.Replay(t, filepath.Join(root, "ruby", "cassettes", name+".yml"), next, opts...)

	enterpriseCassette := filepath.Join(root, "ruby", "cassettes", name+".enterprise.yml")

	if _, err := os.Stat(enterpriseCassette); err == nil {
		enterpriseNext := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			next.ServeHTTP(w, r.WithContext(fromctx.Env.With(r.Context(), "enterprise")))
		})

		vcr.Replay(t, enterpriseCassette, enterpriseNext, opts...)
	}
}

package logger

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/log/logtest"
	"github.com/github/go-kvp"

	"github.com/github/launch/pkg/mu/reqmeta"

	"github.com/pkg/errors"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/observability/ctxstash"
)

func TestPrepareReport_PrefixesOnlyRequestedFields(t *testing.T) {
	l := TestLogger().(*logger)
	ctx := context.Background()

	l.reportFieldTags = map[string]bool{"foo": true}
	preparedReport := l.prepareReport(ctx, errors.New("test"), kvp.String("foo", "bar"), kvp.Int("dc", 42))
	assert.Equal(t, "bar", preparedReport["#foo"])
	assert.Equal(t, "42", preparedReport["dc"])
}

func TestPrepareReport_User_SendsRepoGlobalID(t *testing.T) {
	l := TestLogger().(*logger)
	ctx := context.Background()
	repoGlobalID := "bar"

	preparedReport := l.prepareReport(ctx, errors.New("test"), kvp.String("gh.repo.global_id", repoGlobalID), kvp.Int("dc", 42))

	assert.Equal(t, repoGlobalID, preparedReport["user"])
	assert.Equal(t, repoGlobalID, preparedReport["gh.repo.global_id"])
}

func TestPrepareReport_User_SendsRepoGlobalIDIfMarkedAsTag(t *testing.T) {
	l := TestLogger().(*logger)
	ctx := context.Background()
	repoGlobalID := "bar"
	l.reportFieldTags = map[string]bool{
		"gh.repo.global_id": true,
	}

	preparedReport := l.prepareReport(ctx, errors.New("test"), kvp.String("gh.repo.global_id", repoGlobalID), kvp.Int("dc", 42))

	assert.Equal(t, repoGlobalID, preparedReport["user"])
	assert.Equal(t, repoGlobalID, preparedReport["#gh.repo.global_id"])
}

func TestPrepareReport_User_DoesNotOverride(t *testing.T) {
	l := TestLogger().(*logger)
	ctx := context.Background()

	preparedReport := l.prepareReport(ctx, errors.New("test"), kvp.String("user", "123"), kvp.String("gh.repo.global_id", "bar"), kvp.Int("dc", 42))

	assert.Equal(t, "123", preparedReport["user"])
}

func TestPrepareReport_User_OnlySetsWhenRepoIDSet(t *testing.T) {
	l := TestLogger().(*logger)
	ctx := context.Background()

	preparedReport := l.prepareReport(ctx, errors.New("test"), kvp.Int("dc", 42))

	assert.Equal(t, "", preparedReport["user"])
}

func TestReport_BodyHasExpectedFields(t *testing.T) {
	requestID := "a-request-id"
	app := "launch-app"
	hostname := "my.localhost"

	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		err := json.NewDecoder(r.Body).Decode(&body)
		require.NoError(t, err)

		assert.Equal(t, "An Error", body["message"])
		assert.Equal(t, app, body["app"])
		assert.Equal(t, hostname, body["host"]) // TODO
		assert.Equal(t, requestID, body["#gh.request_id"])
		assert.Equal(t, "a value", body["a-field"])
		assert.Equal(t, "a-kvp-string", body["kvp-string"])
		assert.Equal(t, "kvp_value", body["kvp_field"])
		assert.Equal(t, "go-exceptions", body["reporter-type"])
		assert.Contains(t,
			fmt.Sprintf("%+v", body["exception_detail"]),
			"function:TestReport_BodyHasExpectedFields",
		)
		assert.NotNil(t, body["rollup"])

		w.WriteHeader(http.StatusCreated)
	}))
	defer ts.Close()

	u, _ := url.Parse(ts.URL)
	u.User = url.UserPassword("a-user", "a-password")

	l := New(&Config{
		App:       app,
		ReportURL: u.String(),
		Hostname:  hostname,
		Writer:    os.Stderr,
		FieldTags: map[string]bool{
			"gh.request_id": true,
		},
	})

	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	fields := []kvp.Field{
		kvp.String("gh.request_id", requestID),
		kvp.String("kvp-string", "a-kvp-string"),
	}
	ctx = ctxstash.WithFields(ctx, fields...)
	ctx = ctxstash.WithFields(ctx, kvp.String("kvp_field", "kvp_value"))

	err := l.ReportBlocking(ctx, errors.New("An Error"), kvp.String("a-field", "a value"))
	require.NoError(t, err)
	time.Sleep(time.Millisecond * 10) // Let the reporting channel flush
}

func Test_Debug_Unwraps(t *testing.T) {
	tl, b := logtest.NewTestLogger(t, log.WithLogLevel(log.DebugLevel))
	l := &logger{l: tl}

	// Tired: mu mw.LogWith fields
	ctx := context.WithValue(context.Background(), reqmeta.RMDContextKey, reqmeta.NewRequestMetadata())
	fields := []kvp.Field{
		kvp.String("kvp_field", "kvp-string"),
	}
	ctx = ctxstash.WithFields(ctx, fields...)

	l.Debug(ctx, "debug message", kvp.String("a-field", "a value"))

	assert.Contains(t, b.String(), "Body=\"debug message\"")
	assert.Contains(t, b.String(), "kvp_field=kvp-string")
	assert.Contains(t, b.String(), "a-field=\"a value\"")
}

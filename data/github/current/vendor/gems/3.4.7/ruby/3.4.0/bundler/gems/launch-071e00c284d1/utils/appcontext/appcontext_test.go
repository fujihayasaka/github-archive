package appcontext

import (
	"bytes"
	"context"
	"net/http"
	"regexp"
	"testing"

	"github.com/github/go-kvp"
	"github.com/github/go-reqmeta"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/pkg/mu/muhttp/mw"

	"github.com/github/launch/observability/azpcorrelation"
	"github.com/github/launch/observability/ctxstash"

	"github.com/github/launch/utils/testutils"
)

var md = ApplicationMetadata{
	ServiceName:  "one",
	Environment:  "test-env",
	BuildVersion: "test-ver",
	ObservabilityFields: map[string]string{
		"test-one": "test-one-va",
	},
	MuVersion: "test-mu",
}

func TestInitializeContextFromMetadata(t *testing.T) {
	ctx := context.Background()
	ctx, err := Initialize(ctx, md)
	require.NoError(t, err)

	l := testutils.NewRecordingLogger()

	l.Logger.Log(ctx, "hi")

	msg := l.String()
	assert.Contains(t, msg, "app=launch")
	assert.Contains(t, msg, "sha=test-ver")
	assert.Contains(t, msg, "mu=test-mu")
	assert.Contains(t, msg, "host=")
	assert.Regexp(t, regexp.MustCompile(`\brequest_id=\S+\b`), msg)

	assert.NotEqual(t, "", mw.GetGitHubRequestID(ctx))
}

func TestIDPropagation(t *testing.T) {
	// setup original context with all IDs
	ctx, err := Initialize(context.Background(), md)
	require.NoError(t, err)
	ctx = azpcorrelation.WithVSSCorrelationID(ctx, "test-e2e-id")

	// create new context
	ctx2 := Fork(ctx)

	assert.Equal(t, mw.GetGitHubRequestID(ctx), mw.GetGitHubRequestID(ctx2), "should copy request ID")
	assert.Equal(t, "test-e2e-id", azpcorrelation.GetOrMakeVSSCorrelationID(ctx), "should copy VSS E2E ID")
}

func TestForkDetachesCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	frk := Fork(ctx)

	cancel()

	assert.Equal(t, "context canceled", ctx.Err().Error())
	assert.Nil(t, frk.Err()) // Not canceled
}

func TestCopyRequestMetadata_IncludesCorrectRequestMetadata(t *testing.T) {
	l := testutils.NewRecordingLogger()

	ctxOrig, _ := Initialize(context.Background(), ApplicationMetadata{})
	ctxOrig = ctxstash.WithFields(ctxOrig, kvp.Bool("common", true))

	ctx1 := CopyRequestMetadata(ctxOrig)
	ctx2 := CopyRequestMetadata(ctxOrig)

	ctx1 = ctxstash.WithFields(ctx1, kvp.Bool("one", true))
	ctx2 = ctxstash.WithFields(ctx2, kvp.Bool("two", true))

	l.Logger.Log(ctx1, "log1")
	l.Logger.Log(ctx2, "log2")

	ctxOrig = ctxstash.WithFields(ctxOrig, kvp.Bool("orig", true))
	ctxOrig = ctxstash.WithFields(ctxOrig, kvp.Bool("orig-go", true))
	l.Logger.Log(ctxOrig, "logOrig")

	msg := l.String()

	assert.Contains(t, msg, "common=true one=true")  // ctx1
	assert.Contains(t, msg, "common=true two=true")  // ctx2
	assert.Contains(t, msg, "common=true orig=true") // ctxOrig

	// Validate we don't cross-contaminate the mu/kvp based RMD
	assert.NotRegexp(t, "Body=log1.*two=true", msg)    // ctx1 does not have ctx2
	assert.NotRegexp(t, "Body=log1.*orig=true", msg)   // ctx1 does not have orig
	assert.NotRegexp(t, "Body=log2.*one=true", msg)    // ctx2 does not have ctx1
	assert.NotRegexp(t, "Body=log2.*orig=true", msg)   // ctx2 does not have orig
	assert.NotRegexp(t, "Body=logOrig.*one=true", msg) // ctxOrig does not have ctx1
	assert.NotRegexp(t, "Body=logOrig.*two=true", msg) // ctxOrig does not have ctx2

	// Validate we don't cross-contaminate the go-kvp based RMD
	assert.NotRegexp(t, "Body=log1.*two-go=true", msg)    // ctx1 does not have ctx2
	assert.NotRegexp(t, "Body=log1.*orig-go=true", msg)   // ctx1 does not have orig
	assert.NotRegexp(t, "Body=log2.*one-go=true", msg)    // ctx2 does not have ctx1
	assert.NotRegexp(t, "Body=log2.*orig-go=true", msg)   // ctx2 does not have orig
	assert.NotRegexp(t, "Body=logOrig.*one-go=true", msg) // ctxOrig does not have ctx1
	assert.NotRegexp(t, "Body=logOrig.*two-go=true", msg) // ctxOrig does not have ctx2
}

func TestCopyRequestMetadata_KeepsCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	copy := CopyRequestMetadata(ctx)

	cancel()

	assert.Equal(t, "context canceled", ctx.Err().Error())
	assert.Equal(t, "context canceled", copy.Err().Error()) // Copy has been cancelled
}

func TestCopyRequestMetadata_KeepsAZPCorrelation(t *testing.T) {
	ctx := azpcorrelation.WithVSSCorrelationID(context.Background(), "test-e2e-id")
	copy := CopyRequestMetadata(ctx)

	ctxCor := ctxstash.From(ctx).Correlations().VSS.CorrelationID
	copyCor := ctxstash.From(copy).Correlations().VSS.CorrelationID

	assert.Equal(t, ctxCor, copyCor)
}

func TestSetupServiceContext_SetsRequestMetadata(t *testing.T) {
	req, err := http.NewRequest("POST", "http://localhost/test", bytes.NewBufferString("hello world1"))
	require.NoError(t, err)

	SetupServiceContext(req)

	rmeta, ok := reqmeta.GetRequestMetadata(req.Context())
	assert.True(t, ok)
	assert.NotNil(t, rmeta)
}

func TestEnsureRequestID(t *testing.T) {
	got := EnsureRequestID(context.Background())

	gotReqID, ok := got.Value(mw.RequestIDKey).(string)
	require.True(t, ok, "there should be a request ID in the ctx")
	require.Contains(t,
		ctxstash.From(got).Fields(),
		kvp.String("gh.request_id", gotReqID),
		"there should be a request ID in the log fields",
	)

	wantReqID := gotReqID
	got = EnsureRequestID(got) // do it again
	// the request id shouldn't have changed
	gotReqID, ok = got.Value(mw.RequestIDKey).(string)
	require.True(t, ok, "there should be a request ID in the ctx")
	require.Equal(t, wantReqID, gotReqID)
	require.Contains(t,
		ctxstash.From(got).Fields(),
		kvp.String("gh.request_id", gotReqID),
		"there should be a request ID in the log fields",
	)
}

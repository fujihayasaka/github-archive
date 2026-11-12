package githubtwirp

import (
	"errors"
	"testing"

	"github.com/github/go-stats"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
)

// counterCapture records calls to Counter for test assertions.
type counterCapture struct {
	stats.NullClient
	calls []counterCall
}

type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

func (c *counterCapture) Counter(key string, tags stats.Tags, value int64) {
	c.calls = append(c.calls, counterCall{key: key, tags: tags, value: value})
}

func newObsvWithCapture() (observability.Exporters, *counterCapture) {
	obsv := observability.NewNoopExporters()
	capture := &counterCapture{}
	obsv.Statter = capture
	return obsv, capture
}

type testActors struct{ owner, repo, actor int64 }

func (a testActors) GetOwnerID() int64      { return a.owner }
func (a testActors) GetRepositoryID() int64 { return a.repo }
func (a testActors) GetActorID() int64      { return a.actor }

func TestIsFailOpenEligible(t *testing.T) {
	tests := []struct {
		name         string
		err          error
		expectedOK   bool
		expectedCode string
	}{
		{
			name: "nil error",
			err:  nil,
		},
		{
			name: "plain error",
			err:  errors.New("something broke"),
		},
		{
			name: "customer selection required",
			err:  ErrCustomerSelectionRequired,
		},
		{
			name:         "twirp Internal",
			err:          twirp.InternalError("limiter unavailable"),
			expectedOK:   true,
			expectedCode: "internal",
		},
		{
			name:         "twirp Unavailable",
			err:          twirp.NewError(twirp.Unavailable, "service down"),
			expectedOK:   true,
			expectedCode: "unavailable",
		},
		{
			name:         "twirp DeadlineExceeded",
			err:          twirp.NewError(twirp.DeadlineExceeded, "timeout"),
			expectedOK:   true,
			expectedCode: "deadline_exceeded",
		},
		{
			name: "twirp NotFound",
			err:  twirp.NotFoundError("not found"),
		},
		{
			name: "twirp InvalidArgument",
			err:  twirp.InvalidArgumentError("field", "bad"),
		},
		{
			name: "twirp FailedPrecondition",
			err:  twirp.FailedPrecondition.Error("nope"),
		},
		{
			name:         "wrapped twirp Internal",
			err:          errors.Join(errors.New("wrapper"), twirp.InternalError("limiter unavailable")),
			expectedOK:   true,
			expectedCode: "internal",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ok, code := isFailOpenEligible(tt.err)
			assert.Equal(t, tt.expectedOK, ok)
			assert.Equal(t, tt.expectedCode, code)
		})
	}
}

func TestShouldFailOpenOnQuotaError(t *testing.T) {
	ctx := t.Context()

	t.Run("nil error returns false", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: true,
		})

		result := ShouldFailOpenOnQuotaError(ctx, nil, ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.False(t, result)
		assert.Empty(t, capture.calls)
	})

	t.Run("non-eligible error returns false even with flag enabled", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: true,
		})

		result := ShouldFailOpenOnQuotaError(ctx, errors.New("some invariant error"), ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.False(t, result)
		assert.Empty(t, capture.calls)
	})

	t.Run("transient twirp error with flag disabled returns false", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: false,
		})

		err := twirp.NewError(twirp.Unavailable, "limiter service down")
		result := ShouldFailOpenOnQuotaError(ctx, err, ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.False(t, result)
		assert.Empty(t, capture.calls)
	})

	t.Run("transient twirp error with flag enabled returns true and emits metric", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: true,
		})

		err := twirp.NewError(twirp.Unavailable, "limiter service down")
		result := ShouldFailOpenOnQuotaError(ctx, err, ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.True(t, result)

		require.Len(t, capture.calls, 1)
		assert.Equal(t, "events.quota_check_fail_open", capture.calls[0].key)
		assert.Equal(t, "quota_check", capture.calls[0].tags["resource"])
		assert.Equal(t, "unavailable", capture.calls[0].tags["error_code"])
	})

	t.Run("twirp Internal with flag enabled returns true", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: true,
		})

		err := twirp.InternalError("connection refused")
		result := ShouldFailOpenOnQuotaError(ctx, err, ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.True(t, result)

		require.Len(t, capture.calls, 1)
		assert.Equal(t, "events.quota_check_fail_open", capture.calls[0].key)
		assert.Equal(t, "quota_check", capture.calls[0].tags["resource"])
		assert.Equal(t, "internal", capture.calls[0].tags["error_code"])
	})

	t.Run("twirp DeadlineExceeded with flag enabled returns true", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: true,
		})

		err := twirp.NewError(twirp.DeadlineExceeded, "timeout")
		result := ShouldFailOpenOnQuotaError(ctx, err, ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.True(t, result)

		require.Len(t, capture.calls, 1)
		assert.Equal(t, "events.quota_check_fail_open", capture.calls[0].key)
		assert.Equal(t, "quota_check", capture.calls[0].tags["resource"])
		assert.Equal(t, "deadline_exceeded", capture.calls[0].tags["error_code"])
	})

	t.Run("twirp FailedPrecondition is not transient, returns false", func(t *testing.T) {
		obsv, capture := newObsvWithCapture()
		ffClient := featureflags.NewNoopClient(map[string]bool{
			featureflags.CopilotSWEAgentLimiterFailOpen: true,
		})

		err := twirp.FailedPrecondition.Error("insufficient quota")
		result := ShouldFailOpenOnQuotaError(ctx, err, ffClient, obsv, testActors{1, 2, 42}, "quota_check")
		assert.False(t, result)
		assert.Empty(t, capture.calls)
	})
}

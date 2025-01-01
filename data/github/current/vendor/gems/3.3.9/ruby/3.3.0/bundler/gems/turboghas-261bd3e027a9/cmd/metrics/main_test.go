package main

import (
	"context"
	"strconv"
	"testing"
	"time"

	"github.com/github/go-stats"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/turboghas/internal/dbtest"
	"github.com/github/turboghas/internal/fromctx"
	"github.com/github/turboghas/internal/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func TestPercent(t *testing.T) {
	require.Equal(t, "100%", percent(10, 10))
	require.Equal(t, "50%", percent(5, 10))
	require.Equal(t, "51%", percent(51, 100))
	require.Equal(t, "25%", percent(2.5, 10.0))
	require.Equal(t, "0%", percent(0, 10))
	require.Equal(t, "n/a", percent(10, 0))
}

type mockPublisher struct {
	mock.Mock
}

var _ Publisher = &mockPublisher{}

func (m *mockPublisher) Publish(msg protoreflect.ProtoMessage, opts ...hydro.PublishOption) error {
	args := m.Called(msg, opts)
	return args.Error(0)
}

type mockStatter struct {
	stats.NullClient
	mock.Mock
}

func (e *mockStatter) Distribution(key string, tags stats.Tags, value float64) {
	e.Mock.Called(key, tags, value)
}

func (e *mockStatter) Gauge(key string, tags stats.Tags, value int64) {
	e.Mock.Called(key, tags, value)
}

func (e *mockStatter) Counter(key string, tags stats.Tags, value int64) {
	e.Mock.Called(key, tags, value)
}

func (e *mockStatter) WithTags(tags stats.Tags) stats.Client {
	e.Mock.Called(tags)
	return e
}

var _ stats.Client = &mockStatter{}

type noErrors struct {
	t *testing.T
}

func (n *noErrors) Report(ctx context.Context, err error, payload map[string]string) error {
	require.NoError(n.t, err)
	return nil
}

var _ fromctx.ReportException = &noErrors{}

func TestSummarize(t *testing.T) {
	db := dbtest.Seed(t)
	ctx := fromctx.ExceptionReporter.With(context.Background(), &noErrors{t: t})

	{
		_, err := db.Exec(`UPDATE tg_contributions SET pushed_at = NOW() - INTERVAL 10 DAY WHERE user_id = 1`)
		require.NoError(t, err)
	}

	// ignore outsider data
	{
		_, err := db.Exec(`DELETE FROM tg_entities WHERE entity_id != 1`)
		require.NoError(t, err)
	}

	const maximumCommitters = 7
	const activeCommitters = 4

	c := mocks.Cleanup(t, &mockStatter{})
	c.On("Distribution", "metrics.recent_committer_ratio.active", stats.Tags{"activity": "true"}, float64(activeCommitters-1)/activeCommitters)
	c.On("Distribution", "metrics.recent_committer_ratio.maximum", stats.Tags{"activity": "true"}, float64(maximumCommitters-1)/maximumCommitters)

	// 90 days is 12 buckets, newest -> oldest
	for i, metric := range []int64{maximumCommitters - 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0} {
		c.On("Counter", "metrics.contributors.count", stats.Tags{"bucket": strconv.Itoa(i), "activity": "true"}, metric)
	}
	for i, metric := range []float64{float64(maximumCommitters-1) / maximumCommitters, float64(1) / maximumCommitters, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0} {
		c.On("Distribution", "metrics.contributors.ratio", stats.Tags{"bucket": strconv.Itoa(i), "activity": "true"}, metric)
	}

	c.On("Gauge", "metrics.total_committers.active", stats.Tags(nil), int64(activeCommitters))
	c.On("Gauge", "metrics.total_committers.maximum", stats.Tags(nil), int64(maximumCommitters))

	ctx = fromctx.Statter.With(ctx, c)

	now := time.Now()

	p := mocks.Cleanup(t, &mockPublisher{})
	p.On("Publish", &v0.Summary{
		EntityId:          1,
		EntityType:        "Business",
		ActiveCommitters:  activeCommitters,
		MaximumCommitters: maximumCommitters,
		StartedAt:         timestamppb.New(now),
	}, []hydro.PublishOption(nil)).Return(nil)

	p.On("Publish", &v0.Committers{
		EntityId:   1,
		EntityType: "Business",
		Committers: []*v0.Committers_Committer{
			// emu users
			{UserId: 6, Active: true, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour))},
			{UserId: 7, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour))},
			// users
			{UserId: 1, Active: true, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour).Add(-10 * 24 * time.Hour))},
			{UserId: 5, Active: true, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour))},
			{UserId: 9, Active: true, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour))},
			{UserId: 2, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour))},
			{UserId: 10, PushedAt: timestamppb.New(now.Truncate(24 * time.Hour))},
		},
		StartedAt: timestamppb.New(now),
	}, []hydro.PublishOption(nil)).Return(nil)

	require.NoError(t, summarize(ctx, db, p, 1, now))
}

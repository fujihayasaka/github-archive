package fromctx

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/github/turboghas/internal/lag"
	"github.com/github/turboghas/internal/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
)

type mockClient struct {
	mock.Mock
}

func (m *mockClient) Value(ctx context.Context, cluster string) (time.Duration, error) {
	args := m.Called(ctx, cluster)
	return args.Get(0).(time.Duration), args.Error(1)
}

var _ lag.Client = &mockClient{}

func TestNoHeader(t *testing.T) {
	c := mocks.Cleanup(t, &mockClient{})
	v, err := Lag.Delay(Lag.With(t.Context(), c), hydro.Message{})
	require.NoError(t, err)
	require.Zero(t, v)
}

func TestEmptyHeader(t *testing.T) {
	c := mocks.Cleanup(t, &mockClient{})
	v, err := Lag.Delay(Lag.With(t.Context(), c), hydro.Message{Headers: map[string]string{replicationStateHeader: "{}"}})
	require.NoError(t, err)
	require.Zero(t, v)
}

func TestClusterOldMessage(t *testing.T) {
	c := mocks.Cleanup(t, &mockClient{})
	c.On("Value", mocks.IsContext, "repositories").Return(time.Millisecond*430, nil)
	c.On("Value", mocks.IsContext, "issues-pull-requests").Return(time.Millisecond*130, nil)
	header := `{"repositories":{"gtid":"7dc7ab89-7ae2-11ee-98be-b496915f89f4:8418049025","time":1707380814133},"issues-pull-requests":{"gtid":"7dc7ab89-7ae2-11ee-98be-b496915f89f4:8418049025","time":1707380814133}}`
	v, err := Lag.Delay(Lag.With(t.Context(), c), hydro.Message{Headers: map[string]string{replicationStateHeader: header}})
	require.NoError(t, err)
	require.Zero(t, v)
}

func TestClusterLagging(t *testing.T) {
	c := mocks.Cleanup(t, &mockClient{})
	c.On("Value", mocks.IsContext, "repositories").Return(time.Second*2, nil)
	c.On("Value", mocks.IsContext, "issues-pull-requests").Return(time.Millisecond*1130, nil)
	header := fmt.Sprintf(`{"repositories":{"gtid":"7dc7ab89-7ae2-11ee-98be-b496915f89f4:8418049025","time":%d},"issues-pull-requests":{"gtid":"7dc7ab89-7ae2-11ee-98be-b496915f89f4:8418049025","time":%d}}`, time.Now().UnixMilli(), time.Now().UnixMilli())
	v, err := Lag.Delay(Lag.With(t.Context(), c), hydro.Message{Headers: map[string]string{replicationStateHeader: header}})
	require.NoError(t, err)
	require.Equal(t, time.Second*2, v.Round(time.Second))
}

func TestCacheDelay(t *testing.T) {
	c := mocks.Cleanup(t, &mockClient{})
	c.On("Value", mocks.IsContext, "repositories").Once().Return(time.Second*2, nil)
	ctx := Lag.With(t.Context(), lag.Cache(c, 150*time.Millisecond))
	{
		header := fmt.Sprintf(`{"repositories":{"gtid":"7dc7ab89-7ae2-11ee-98be-b496915f89f4:8418049025","time":%d}}`, time.Now().UnixMilli())
		v, err := Lag.Delay(ctx, hydro.Message{Headers: map[string]string{replicationStateHeader: header}})
		require.NoError(t, err)
		require.Equal(t, time.Second*2, v.Round(time.Second))
	}
	// should not call Value again
	{
		header := fmt.Sprintf(`{"repositories":{"gtid":"7dc7ab89-7ae2-11ee-98be-b496915f89f4:8418049025","time":%d}}`, time.Now().UnixMilli())
		v, err := Lag.Delay(ctx, hydro.Message{Headers: map[string]string{replicationStateHeader: header}})
		require.NoError(t, err)
		require.Equal(t, time.Second*2, v.Round(time.Second))
	}
}

package lag

import (
	"context"
	"io"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/github/turboghas/internal/mocks"
	"github.com/github/turboghas/proto"
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

var _ Client = &mockClient{}

type mockHttpClient struct {
	mock.Mock
}

func (m *mockHttpClient) Do(req *http.Request) (*http.Response, error) {
	args := m.Called(req)
	return args.Get(0).(*http.Response), args.Error(1)
}

var _ proto.HTTPClient = &mockHttpClient{}

func TestValue(t *testing.T) {
	c := mocks.Cleanup(t, &mockHttpClient{})
	c.On("Do", mock.MatchedBy(mocks.Is[*http.Request])).Return(&http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(`{"StatusCode":200,"Value":1.0,"Threshold":1,"Message":""}`)),
	}, nil)
	lag, err := FrenoClient("localhost:0", c).Value(t.Context(), "test")
	require.NoError(t, err)
	require.Equal(t, time.Second, lag)
}

func TestUnknownCluster(t *testing.T) {
	c := mocks.Cleanup(t, &mockHttpClient{})
	c.On("Do", mock.MatchedBy(mocks.Is[*http.Request])).Return(&http.Response{
		StatusCode: http.StatusNotFound,
		Body:       io.NopCloser(strings.NewReader(`{"StatusCode":404,"Value":0,"Threshold":64,"Message":"No such metric"}`)),
	}, nil).Once()
	f := FrenoClient("localhost:0", c)
	lag, err := f.Value(t.Context(), "test")
	require.ErrorIs(t, err, ErrUnknownCluster)
	require.Equal(t, time.Duration(0), lag)
}

func TestCacheClient(t *testing.T) {
	c := mocks.Cleanup(t, &mockHttpClient{})
	c.On("Do", mock.MatchedBy(mocks.Is[*http.Request])).Return(&http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(`{"StatusCode":200,"Value":1.0,"Threshold":1,"Message":""}`)),
	}, nil).Once()
	client := Cache(FrenoClient("localhost:0", c), 0)
	{
		lag, err := client.Value(t.Context(), "test")
		require.NoError(t, err)
		require.Equal(t, time.Second, lag)
	}
	{
		lag, err := client.Value(t.Context(), "test")
		require.NoError(t, err)
		require.Equal(t, time.Second, lag)
	}
}

func TestCacheClientMinTTL(t *testing.T) {
	c := mocks.Cleanup(t, &mockHttpClient{})
	c.On("Do", mock.MatchedBy(mocks.Is[*http.Request])).Return(&http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(`{"StatusCode":200,"Value":0,"Threshold":1,"Message":""}`)),
	}, nil).Once()
	client := Cache(FrenoClient("localhost:0", c), time.Second)
	{
		lag, err := client.Value(t.Context(), "test")
		require.NoError(t, err)
		require.Equal(t, time.Duration(0), lag)
	}
	{
		lag, err := client.Value(t.Context(), "test")
		require.NoError(t, err)
		require.Equal(t, time.Duration(0), lag)
	}
}

func TestFloatValue(t *testing.T) {
	c := mocks.Cleanup(t, &mockHttpClient{})
	c.On("Do", mock.MatchedBy(mocks.Is[*http.Request])).Return(&http.Response{
		StatusCode: http.StatusOK,
		Body:       io.NopCloser(strings.NewReader(`{"StatusCode":200,"Value":0.001,"Threshold":1,"Message":""}`)),
	}, nil)
	lag, err := FrenoClient("localhost:0", c).Value(t.Context(), "test")
	require.NoError(t, err)
	require.Equal(t, time.Millisecond, lag)
}

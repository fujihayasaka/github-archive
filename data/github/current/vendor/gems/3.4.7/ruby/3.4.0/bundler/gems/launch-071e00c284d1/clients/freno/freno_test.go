package freno

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync"
	"testing"
	"time"

	circuit "github.com/rubyist/circuitbreaker"
	"github.com/stretchr/testify/require"

	"github.com/github/launch/utils/apphttp"
	"github.com/github/launch/utils/testutils"
)

func TestFrenoClient(t *testing.T) {
	cases := []struct {
		statusCode     int
		body           string
		canWrite       bool
		replicationLag time.Duration
		threshold      time.Duration
		message        string
		defaultCluster string
	}{
		{
			statusCode:     200,
			body:           `{"StatusCode":200,"Value":0.341822,"Threshold":1,"Message":""}`,
			canWrite:       true,
			replicationLag: 341822 * time.Microsecond,
			threshold:      time.Second,
			message:        "",
		},
		{
			statusCode:     200,
			body:           `{"StatusCode":200,"Value":0.341822,"Threshold":1,"Message":""}`,
			canWrite:       true,
			replicationLag: 341822 * time.Microsecond,
			threshold:      time.Second,
			message:        "",
			defaultCluster: "staffship",
		},
		{
			statusCode:     404,
			body:           `{"StatusCode":404,"Value":0,"Threshold":0,"Message":"No such metric"}`,
			canWrite:       false,
			replicationLag: 0 * time.Microsecond,
			threshold:      0,
			message:        "No such metric",
		},
		{
			statusCode:     404,
			body:           `{"StatusCode":404,"Value":0,"Threshold":0,"Message":"No such metric"}`,
			canWrite:       false,
			replicationLag: 0 * time.Microsecond,
			threshold:      0,
			message:        "No such metric",
			defaultCluster: "staffship",
		},
		{
			statusCode:     417,
			body:           `{"StatusCode":417,"Value":0,"Threshold":0,"Message":"App denied"}`,
			canWrite:       false,
			replicationLag: 0 * time.Microsecond,
			threshold:      0,
			message:        "App denied",
		},
		{
			statusCode:     417,
			body:           `{"StatusCode":417,"Value":0,"Threshold":0,"Message":"App denied"}`,
			canWrite:       false,
			replicationLag: 0 * time.Microsecond,
			threshold:      0,
			message:        "App denied",
			defaultCluster: "staffship",
		},
		{
			statusCode:     429,
			body:           `{"StatusCode":429,"Value":13.341822,"Threshold":0.5,"Message":"Threshold exceeded"}`,
			canWrite:       false,
			replicationLag: 13341822 * time.Microsecond,
			threshold:      500 * time.Millisecond,
			message:        "Threshold exceeded",
		},
		{
			statusCode:     429,
			body:           `{"StatusCode":429,"Value":13.341822,"Threshold":0.5,"Message":"Threshold exceeded"}`,
			canWrite:       false,
			replicationLag: 13341822 * time.Microsecond,
			threshold:      500 * time.Millisecond,
			message:        "Threshold exceeded",
			defaultCluster: "staffship",
		},
	}

	for _, tc := range cases {
		name := strconv.Itoa(tc.statusCode)
		if tc.defaultCluster != "" {
			name += " with default cluster"
		}

		t.Run(name, func(t *testing.T) {
			hdl := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				require.Equal(t, http.MethodGet, r.Method)

				if tc.defaultCluster != "" {
					require.Equal(t, "/check/launch/mysql/"+tc.defaultCluster, r.URL.Path)
				} else {
					require.Equal(t, "/check/launch/mysql/collab", r.URL.Path)
				}

				w.WriteHeader(tc.statusCode)
				_, err := w.Write([]byte(tc.body))
				require.NoError(t, err)
			})

			srv := httptest.NewServer(hdl)
			defer srv.Close()

			ctx := context.Background()

			freno, err := NewClient(srv.URL, tc.defaultCluster, &ClientHooks{}, apphttp.NewClient(), testutils.NewNoopBreaker())
			require.NoError(t, err)
			res, err := freno.Check(ctx, "collab")
			require.NoError(t, err)
			require.Equal(t, tc.canWrite, res.CanWrite)
			require.Equal(t, tc.statusCode, res.StatusCode)
			require.Equal(t, tc.replicationLag, res.ReplicationLag)
			require.Equal(t, tc.threshold, res.Threshold)
			require.Equal(t, tc.message, res.Message)
		})
	}
}

func TestFrenoClient500Response(t *testing.T) {
	hdl := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		require.Equal(t, http.MethodGet, r.Method)
		require.Equal(t, r.URL.Path, "/check/launch/mysql/collab")
		w.WriteHeader(http.StatusInternalServerError)
		_, err := w.Write([]byte("OOM"))
		require.NoError(t, err)
	})

	srv := httptest.NewServer(hdl)
	defer srv.Close()

	ctx := context.Background()

	freno, err := NewClient(srv.URL, "", &ClientHooks{}, apphttp.NewClient(), testutils.NewNoopBreaker())
	require.NoError(t, err)
	res, err := freno.Check(ctx, "collab")
	require.Error(t, err)
	require.Nil(t, res)
}

func TestFrenoClientSingleFlight(t *testing.T) {
	checkIsSingleFlight := make(chan struct{}, 1)
	unblock := make(chan struct{})

	hdl := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-unblock
		select {
		case checkIsSingleFlight <- struct{}{}:
			// we're the only one here
			defer func() {
				<-checkIsSingleFlight
			}()
		default:
			t.Error("more than 1 concurrent call made it through to the server")
			return
		}
		require.Equal(t, http.MethodGet, r.Method)
		require.Equal(t, r.URL.Path, "/check/launch/mysql/collab")
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte(`{"StatusCode":200,"Value":0.341822,"Threshold":1,"Message":""}`))
		require.NoError(t, err)

	})

	srv := httptest.NewServer(hdl)
	defer srv.Close()

	ctx := context.Background()

	freno, err := NewClient(srv.URL, "", &ClientHooks{}, apphttp.NewClient(), testutils.NewNoopBreaker())
	require.NoError(t, err)

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		res, err := freno.Check(ctx, "collab")
		require.NoError(t, err)
		require.Equal(t, true, res.CanWrite)
		require.Equal(t, 200, res.StatusCode)
		require.Equal(t, 341822*time.Microsecond, res.ReplicationLag)
		require.Equal(t, time.Second, res.Threshold)
		require.Equal(t, "", res.Message)
	}()
	time.Sleep(100 * time.Millisecond)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			res, err := freno.Check(ctx, "collab")
			require.NoError(t, err)
			require.Equal(t, true, res.CanWrite)
			require.Equal(t, 200, res.StatusCode)
			require.Equal(t, 341822*time.Microsecond, res.ReplicationLag)
			require.Equal(t, time.Second, res.Threshold)
			require.Equal(t, "", res.Message)
		}()
	}
	close(unblock)
	wg.Wait()
}

func TestFrenoClientSingleFlightInBreaker(t *testing.T) {
	checkIsSingleFlight := make(chan struct{}, 1)
	unblock := make(chan struct{})

	hdl := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		<-unblock
		select {
		case checkIsSingleFlight <- struct{}{}:
			// we're the only one here
			defer func() {
				<-checkIsSingleFlight
			}()
		default:
			t.Error("more than 1 concurrent call made it through to the server")
			return
		}
		require.Equal(t, http.MethodGet, r.Method)
		require.Equal(t, r.URL.Path, "/check/launch/mysql/collab")
		w.WriteHeader(http.StatusOK)
		_, err := w.Write([]byte(`{"StatusCode":200,"Value":0.341822,"Threshold":1,"Message":""}`))
		require.NoError(t, err)

	})

	srv := httptest.NewServer(hdl)
	defer srv.Close()

	ctx := context.Background()

	breaker := circuit.NewRateBreaker(0.1, 1)

	freno, err := NewClient(srv.URL, "", &ClientHooks{}, apphttp.NewClient(), breaker)
	require.NoError(t, err)

	// force the breaker to open, all calls should error
	breaker.Break()

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		res, err := freno.Check(ctx, "collab")
		require.Error(t, err)
		require.Contains(t, err.Error(), "breaker open")
		require.Nil(t, res)
	}()
	time.Sleep(100 * time.Millisecond)
	for i := 0; i < 20; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			res, err := freno.Check(ctx, "collab")
			require.Error(t, err)
			require.Contains(t, err.Error(), "breaker open")
			require.Nil(t, res)
		}()
	}
	close(unblock)
	wg.Wait()
}

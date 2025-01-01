package aqueduct

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-config"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/hydro"
	hydrotesthelper "github.com/github/notifyd/internal/pkg/hydro/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

func Test_WorkerIntegration(t *testing.T) {
	r := require.New(t)

	if testing.Short() {
		t.Skip("skipping integration test")
	}
	Reset(t)
	hydroConfig := hydro.Config{}
	err := config.Load(&hydroConfig)
	r.NoError(err)
	hydrotesthelper.Reset(t, hydroConfig.KafkaAdminDev)

	// We make this cancellable so that the worker pool exits after this function finishes, we don't
	// want it to be lurking in the background forever.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	t.Setenv("AQUEDUCT_QUEUE", "retries")
	clientConfig := ClientConfig{}
	err = config.Load(&clientConfig)
	r.NoError(err)
	client, err := NewClient(clientConfig, log.NewNullLogger(), stats.NullStatter)
	r.NoError(err)

	workerConfig := WorkerConfig{}
	err = config.Load(&workerConfig)
	r.NoError(err)
	wg := sync.WaitGroup{}
	wg.Add(1)
	handler := func(_ context.Context, rr aqueduct.ReceiveResult) error {
		t.Log("processing test job")
		// We use assert instead of require because this will run on a different goroutine than the
		// current one. require wouldn't work as it relies on panic handling, which can only be done
		// per goroutine.
		assert.Equal(t, "foo", string(rr.Payload))
		wg.Done()

		return nil
	}

	worker, err := NewWorker(workerConfig, client, log.NewNullLogger(), stats.NullStatter, handler)
	require.NoError(t, err)
	pool := NewPool(workerConfig.ParallelJobs, logs.NullTelem, worker)

	// And then we process it just making sure that the received payload is the same we delivered.
	t.Log("starting test consumer")
	pool.Run(ctx)

	// We send a single test job it is slightly delayed so that we make sure the test consumer has
	// time to start.
	time.Sleep(500 * time.Millisecond)
	t.Log("sending test job")
	job := aqueduct.Job{
		App:     workerConfig.App,
		Queue:   workerConfig.Queue,
		Payload: []byte("foo"),
	}
	_, err = client.Send(ctx, job)
	r.NoError(err)

	wg.Wait()
}

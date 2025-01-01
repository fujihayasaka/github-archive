package workerpool

import (
	"context"
	"sync"
	"sync/atomic"
	"time"

	errs "github.com/pkg/errors"

	"github.com/github/launch/pkg/mu"

	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/appcontext"
)

// NewPool creates a worker pool with a fixed number of worker threads.
// Note: this pool will not be garbage collected until the statter is
func NewPool(count int, maxQueueLength int, log logger.Logger, stats statter.Statter) Workers {
	p := &pool{
		log:   log,
		stats: stats,
		queue: make(chan poolJob, maxQueueLength),
		_done: make(chan struct{}),
		state: int32(0),
		tags:  statter.Tags{workerTypeKey: "pool", "host": mu.AppHost()},
	}
	p.startWorkers(count)
	stats.Periodically(p.reportCounts)
	return p
}

type pool struct {
	log   logger.Logger
	stats statter.Statter

	queue chan poolJob
	_done chan struct{}
	state int32
	wg    sync.WaitGroup

	active int64
	total  int64
	tags   statter.Tags
}

type poolJob struct {
	ctx  context.Context
	name string
	fn   JobFunc

	queuedAt time.Time
}

func (p *pool) Active() int64 {
	return atomic.LoadInt64(&p.active)
}

func (p *pool) startWorkers(count int) {
	p.wg.Add(count)
	p.total = int64(count)
	for i := 0; i < count; i++ {
		go p.work()
	}
}

func (p *pool) work() {
	defer p.wg.Done()
	defer atomic.AddInt64(&p.total, -1)

	for {
		select {
		case job := <-p.queue:
			p.stats.LegacyTiming(job.ctx, jobQueueTimeMetric, p.tags.Merge(statter.Tags{jobNameKey: job.name}), time.Since(job.queuedAt))
			atomic.AddInt64(&p.active, 1)
			run(job.ctx, p.log, p.stats, job.name, job.fn)
			atomic.AddInt64(&p.active, -1)
		default:
			if p.closed() {
				return
			}
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func (p *pool) Run(ctx context.Context, jobName string, job JobFunc) (err error) {
	j := poolJob{
		ctx:      appcontext.Fork(ctx),
		name:     jobName,
		fn:       job,
		queuedAt: time.Now(),
	}

	if p.closed() {
		err := errs.New("Worker pool has been stopped")
		return err
	}

	select {
	case p.queue <- j:
		return nil
	default:
		err := errs.New("Job queue is full!")
		return err
	}
}

func (p *pool) Periodically(interval time.Duration, jobName string, job JobFunc) {
	go runPeriodically(p, interval, jobName, job)
}

func (p *pool) Stop() {
	atomic.StoreInt32(&p.state, 1)
	close(p._done)
	p.wg.Wait()
	close(p.queue)
}

func (p *pool) closed() bool {
	return atomic.LoadInt32(&p.state) == 1
}

func (p *pool) done() <-chan struct{} {
	return p._done
}

func (p *pool) logger() logger.Logger {
	return p.log
}

func (p *pool) reportCounts(statter.Statter) {
	ctx := context.Background()
	active := atomic.LoadInt64(&p.active)
	total := atomic.LoadInt64(&p.total)
	queued := len(p.queue)
	p.stats.Gauge(ctx, activeWorkersGauge, p.tags, active)
	p.stats.Gauge(ctx, totalWorkersGauge, p.tags, total)
	p.stats.Gauge(ctx, jobsQueuedGauge, p.tags, int64(queued))
}

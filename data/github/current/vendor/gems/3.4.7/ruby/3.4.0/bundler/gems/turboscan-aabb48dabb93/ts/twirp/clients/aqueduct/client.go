// Package aqueduct package provides a wrapper around the aqueduct client go.
package aqueduct

import (
	"context"
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	aq "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/pkg/errors"

	"github.com/github/go-stats"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/config"
	"github.com/github/turboscan/ts/indexer"
	managedanalyses "github.com/github/turboscan/ts/managedanalyses/service"
	"github.com/github/turboscan/ts/suggestedfixes"
)

type Queue interface {
	Enqueue(context.Context, aq.Client, aq.Job) (string, error)
}

// Client is a thin wrapper around the Aqueduct client
type Client struct {
	Queue
	aqueduct aq.Client
	app      string
}

type AqueductQueue struct{}

type JobRetrier interface {
	RetryLater(context.Context, EnqueableJob, uint8) (string, error)
}

var _ JobRetrier = (*Client)(nil)

const (
	RetryCountHeader = "X-Retry-Count"
	MaxRetryCount    = 10
)

func NewClient(cfg *config.Config, logger log.Logger, stats stats.Client, rt http.RoundTripper) (*Client, error) {
	aqStat, err := aq.NewStatsConfig(aq.WithStatsClient(stats))
	if err != nil {
		return nil, err
	}

	aqueductOpts := []aq.ClientOption{
		aq.WithClientLogger(logger),
		aq.WithClientStats(aqStat),
		aq.WithHTTPClient(&http.Client{Transport: rt}),
	}

	if cfg.AqueductAPIKey != "" {
		aqueductOpts = append(aqueductOpts, aq.WithAPIKey(cfg.AqueductAPIKey))
	}

	c, err := aq.NewClient(
		cfg.AqueductAddr,
		aqueductOpts...,
	)
	if err != nil {
		return nil, err
	}

	return &Client{
		Queue:    &AqueductQueue{},
		aqueduct: c,
		app:      cfg.AqueductApp,
	}, nil
}

// PerformLater submits the payload
func (c *Client) PerformLater(ctx context.Context, j EnqueableJob) (string, error) {
	return c.send(ctx, j, nil, 0)
}

func (c *Client) PerformLaterAt(ctx context.Context, j EnqueableJob, at time.Time) (string, error) {
	return c.send(ctx, j, &at, 0)
}

func (q *AqueductQueue) Enqueue(ctx context.Context, aqueduct aq.Client, job aq.Job) (string, error) {
	return aqueduct.Send(ctx, job)
}

func (c *Client) RetryLater(ctx context.Context, j EnqueableJob, retryCount uint8) (string, error) {
	backoff := time.Duration(float64(time.Second) * j.GetRetryBackoffFunc()(retryCount))
	at := time.Now().Add(backoff)
	return c.send(ctx, j, &at, retryCount)
}

func (c *Client) send(ctx context.Context, j EnqueableJob, at *time.Time, retryCount uint8) (string, error) {
	p, err := json.Marshal(j)
	if err != nil {
		return "", errors.Wrap(err, "failed to marshal payload")
	}

	job := aq.Job{
		App:     c.app,
		Queue:   j.Queue(),
		Payload: p,
		Headers: map[string]string{
			RetryCountHeader: strconv.FormatUint(uint64(retryCount), 10),
		},
	}
	if at != nil {
		job.DeliverAt = *at
	}

	if slug := tenant.GetTenant(ctx); slug != "" {
		job.Headers[headers.Tenant] = slug
	}
	if tenantID := tenant.GetTenantID(ctx); tenantID != "" {
		job.Headers[headers.TenantID] = tenantID
	}

	jobId, err := c.Enqueue(ctx, c.aqueduct, job)
	if err != nil {
		return "", errors.Wrap(err, "failed to submit job")
	}
	appctx.Logger(ctx).Info("job submitted",
		kvp.String("gh.aqueduct.queue.name", j.Queue()),
		kvp.String("gh.aqueduct.job.id", jobId))
	return jobId, nil

}

// EnqueableJob is the interface that all jobs need to implement
type EnqueableJob interface {
	Name() string
	Queue() string
	Perform(context.Context, *TSServices) error
	GetRepositoryID() *ts.RepositoryEID // Might return nil if the job doesn't have a repository
	GetRetryBackoffFunc() RetryBackoffFunc
}

type DeliveryProcessor interface {
	ProcessDeliveries(ctx context.Context, repoID ts.RepositoryEID, attempt int) error
}

type TSServices struct {
	DeliveryProcessor            DeliveryProcessor
	GetDeliveriesByWorkflowRunID func(ctx context.Context, repoID ts.RepositoryEID, workflowRunID ts.WorkflowRunEID) ([]ts.Delivery, error)
	ManagedAnalyses              *managedanalyses.ManagedAnalyses
	SuggestedFixes               *suggestedfixes.SuggestedFixes
	Aqueduct                     JobPerformer
	Indexer                      *indexer.Service
	IsEnterpriseEnv              bool
}

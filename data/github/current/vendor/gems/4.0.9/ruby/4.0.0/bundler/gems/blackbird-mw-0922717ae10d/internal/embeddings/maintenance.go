package embeddings

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"sync"
	"time"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"

	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/utils"
)

// Only evaluate copilot indexed records whose last requested at timestamp is older than cutoffDays.
const cutoffDays = 21

type Maintenance struct {
	githubClient  github.InternalAPIClient
	repoPublisher *repo.Publisher
	wg            sync.WaitGroup
}

func NewMaintenance(
	githubClient github.InternalAPIClient,
	repoPublisher *repo.Publisher,
) *Maintenance {
	return &Maintenance{
		githubClient:  githubClient,
		repoPublisher: repoPublisher,
	}
}

func (e *Maintenance) Run(ctx context.Context) {
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		defer utils.PanicLogger(ctx)

		ticker := time.NewTicker(15 * time.Second)

		start := &github.CopilotIndexedRepository{} // NB: Must be allocated for the first iteration.
		var err error
		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				cutoffTime := time.Now().Add(-time.Hour * 24 * cutoffDays).UTC()
				if start.LastRequestedAt.Before(cutoffTime) {
					startTime := time.Now()
					if err = e.run(ctx, start, cutoffTime); err != nil {
						logging.Error(ctx, "batch processing failed", kvp.Err(err))
					}
					statting.DistributionMs(
						ctx,
						"batch.processed",
						time.Since(startTime),
						stats.Tags{"error": strconv.FormatBool(err != nil)},
					)
					statting.Gauge(
						ctx,
						"batch.processed.last_requested_at_secs",
						int64(-time.Since(start.LastRequestedAt).Seconds()),
						stats.Tags{"error": strconv.FormatBool(err != nil)},
					)
				}
			}
		}
	}()
}

func (e *Maintenance) Shutdown() {
	e.wg.Wait()
}

func (e *Maintenance) run(ctx context.Context, next *github.CopilotIndexedRepository, cutoffTime time.Time) error {
	const limit = 20
	cirs, err := e.githubClient.GetCopilotIndexedRepositories(ctx, limit, next)
	if err != nil {
		return err
	}

	for _, cir := range cirs {
		recordStart := time.Now()
		innerCtx := logging.With(
			ctx,
			kvp.Uint64("repository_id", uint64(cir.RepositoryID)),
			kvp.Time("last_requested_at", cir.LastRequestedAt),
			kvp.Time("cutoff_time", cutoffTime),
			kvp.Int("limit", limit),
		)
		logging.Info(innerCtx, "processing")

		// Only process records that are older than the cutoff time. Because the records are sorted by
		// (last requested at, repo id) ascending, the first record found that is newer than the cutoff
		// becomes the starting point for the next iteration.
		if cir.LastRequestedAt.After(cutoffTime) {
			logging.Info(innerCtx, "processing aborted", kvp.String("reason", "last requested at after cutoff"))
			*next = *cir
			next.RepositoryID = 0 // NB: The repo id is reset to 0 because the repo id is used exclusively when querying for records.
			return nil
		}

		status, err := e.githubClient.DeleteCopilotIndexedRepository(innerCtx, false, cir)
		if err != nil {
			statting.DistributionMs(ctx, "record.error", time.Since(recordStart), stats.Tags{"operation": "delete"})
			logging.Error(ctx, "processing failed", kvp.String("operation", "delete"), kvp.Err(err))
			return err
		}

		switch status {
		case http.StatusNoContent, http.StatusNotFound:
			if err := e.repoPublisher.PublishChange(innerCtx, cir.RepositoryID, searchpb.RepositoryChanged_ADMIN_REPAIR, ""); err != nil {
				statting.DistributionMs(ctx, "record.error", time.Since(recordStart), stats.Tags{"operation": "publish"})
				logging.Error(ctx, "processing failed", kvp.String("operation", "publish"), kvp.Err(err))
				return err
			}
		case http.StatusMethodNotAllowed:
			// The record is not deletable so its activity timestamp is updated for checking again in the future.
			if _, err := e.githubClient.UpdateCopilotIndexedRepository(innerCtx, cir); err != nil {
				statting.DistributionMs(ctx, "record.error", time.Since(recordStart), stats.Tags{"operation": "update"})
				logging.Error(ctx, "processing failed", kvp.String("operation", "update"), kvp.Err(err))
				return err
			}
		default:
			return fmt.Errorf("unexpected status code: %d", status)
		}

		logging.Info(innerCtx, "processing succeeded")
		statting.DistributionMs(ctx, "record.success", time.Since(recordStart), stats.Tags{"status": strconv.Itoa(status)})

		// NB: assign next on each iteration to the last record processed.
		*next = *cir
	}

	return nil
}

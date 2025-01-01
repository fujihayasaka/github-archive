package repository

import (
	"context"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/jinzhu/gorm"

	"github.com/github/go-stats"
	"github.com/github/turboscan/ts/elasticsearch"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/pkg/errors"
)

type RepositoryCleanupService struct {
	db *gorm.DB

	sarifStore store.SarifStore
	es         *elasticsearch.Service
	dr         *DeletedRepositoryService
	deadline   time.Time
}

// ErrCleanupStopped corresponds to situations where we decide to stop cleanup
// without there being an error.
// For instance if the deadline has passed or if there is an ongoing ES migration.
var ErrCleanupStopped = errors.New("cleanup stopped without error")

// NewRepositoryCleanupService creates a repository cleanup service with the given parameters
func NewRepositoryCleanupService(db *gorm.DB, sarifStore store.SarifStore, es *elasticsearch.Service, dr *DeletedRepositoryService) *RepositoryCleanupService {
	s := &RepositoryCleanupService{
		db:         db,
		sarifStore: sarifStore,
		es:         es,
		dr:         dr,
	}
	return s
}

// SetDeadlineFromNow sets the deadline based on the specified duration
func (s *RepositoryCleanupService) SetDeadlineFromNow(dur time.Duration) {
	s.deadline = time.Now().Add(dur)
}

// DeadlineExceeded returns true if the deadline was exceeded
func (s *RepositoryCleanupService) DeadlineExceeded() bool {
	if s.deadline.IsZero() {
		return false
	}

	return time.Now().After(s.deadline)
}

// WaitOnMySQLWrite waits until we are ok to write to MySQL by checking freno.
// Will check the deadline as well and return an error if the deadline is reached.
func (s *RepositoryCleanupService) WaitOnMySQLWrite(ctx context.Context) error {
	var err error
	var canWrite bool
	for !canWrite {
		if s.DeadlineExceeded() {
			appctx.Logger(ctx).Info("Deadline exceeded - stopping execution")
			return ErrCleanupStopped
		}
		canWrite, err = appctx.Throttler(ctx).CanWrite(ctx)
		if err != nil {
			appctx.Logger(ctx).WithError(err).Error("Error checking Freno")
			appctx.Stats(ctx).Counter("repo_cleanup.freno_error", stats.Tags{}, 1)
			time.Sleep(1 * time.Second)
		}
		if !canWrite {
			appctx.Logger(ctx).Info("Waiting on Freno")
			appctx.Stats(ctx).Counter("repo_cleanup.throttled", stats.Tags{}, 1)
			time.Sleep(1 * time.Second)
		}
	}
	return nil
}

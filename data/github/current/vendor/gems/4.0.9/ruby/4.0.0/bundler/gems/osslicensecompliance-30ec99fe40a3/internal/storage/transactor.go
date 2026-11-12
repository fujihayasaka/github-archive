package storage

import (
	"context"
	"database/sql"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
)

// Step represents a single operation to be executed within a database transaction.
// This is used to abstract out the storage operations from the higher level code
// that uses them.
type Step interface {
	// Execute is the method that performs the operation of the step.
	Execute(ctx context.Context, tx *sql.Tx) error
}

// PostUpdateHook is a function that's called after all of the database steps
// have completed, but before the transaction is committed. In our code,
// this is most commonly used to publish Hydro events. If the hook returns
// an error, the transaction will be rolled back and the error will be returned
// from the Transactor's Execute method.
type PostUpdateHook func(ctx context.Context) error

// Transactor manages the execution of multiple storage steps within a single database transaction.
type Transactor struct {
	steps  []Step
	db     *sql.DB
	ctx    context.Context
	logger log.Logger
	hooks  []PostUpdateHook
}

// NewTransactor creates a new Transactor with the given context.
func (s *Storage) NewTransactor(ctx context.Context) *Transactor {
	return &Transactor{
		db:     s.db,
		ctx:    ctx,
		logger: s.logger,
	}
}

// AddStep adds a database operation step to the transaction.
func (t *Transactor) AddStep(step Step) {
	t.steps = append(t.steps, step)
}

// AddPostUpdateHook adds a hook function to be called after the steps are complete,
// but before the transaction is committed. This is typically used for publishing events.
func (t *Transactor) AddPostUpdateHook(hook PostUpdateHook) {
	t.hooks = append(t.hooks, hook)
}

// Execute runs all of the steps and hooks within a database transaction.
func (t *Transactor) Execute() error {
	tx, err := t.db.BeginTx(t.ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}

	defer func() {
		if err != nil {
			t.safeRollback(tx)
		}
	}()

	for _, step := range t.steps {
		err = step.Execute(t.ctx, tx)
		if err != nil {
			return fmt.Errorf("failed to execute step: %w", err)
		}
	}

	// Call hooks if provided
	for _, hook := range t.hooks {
		err = hook(t.ctx)
		if err != nil {
			return fmt.Errorf("failed to execute hook: %w", err)
		}
	}

	err = tx.Commit()
	if err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}

	return nil
}

func (t *Transactor) safeRollback(tx *sql.Tx) {
	rollbackErr := tx.Rollback()
	if rollbackErr != nil {
		t.logger.Error("failed to rollback transaction", kvp.Err(rollbackErr))
	}
}

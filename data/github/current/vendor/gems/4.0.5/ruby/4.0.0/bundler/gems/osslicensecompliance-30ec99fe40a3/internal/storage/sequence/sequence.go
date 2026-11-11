// Package sequence provides sequence number generation for alerts.
package sequence

import (
	"context"
	"database/sql"
	"fmt"
	"math"
	"time"

	"github.com/go-errors/errors"
)

// Generator provides sequential alert number generation for repositories.
type Generator interface {
	Next(ctx context.Context, repositoryID uint64) (uint32, error)
}

// MySQLGenerator implements Generator using MySQL database for storage.
type MySQLGenerator struct {
	db *sql.DB
}

// NewMySQLGenerator creates a new MySQLGenerator with the given database connection.
func NewMySQLGenerator(db *sql.DB) *MySQLGenerator {
	return &MySQLGenerator{db: db}
}

// Next generates the next sequential alert number for the given repository.
// Returns the next available number (starting from 1 for new repositories).
func (g *MySQLGenerator) Next(ctx context.Context, repositoryID uint64) (uint32, error) {
	return g.incr(ctx, repositoryID, 1)
}

// incr increments the sequence counter for a repository by the specified count (default 1).
// Copied wholesale from https://github.com/github/turboscan/blob/main/ts/sequence/mysql/mysql.go
func (g *MySQLGenerator) incr(ctx context.Context, repositoryID uint64, count uint32) (uint32, error) {
	// This query performs an atomic upsert operation:
	// - If repository_id doesn't exist: INSERT a new row with number = count
	// - If repository_id exists: UPDATE number = number + count
	//
	// The LAST_INSERT_ID(number + count) trick captures the new incremented value
	// during UPDATE operations, allowing us to retrieve it via LastInsertId().
	// This ensures the increment and value retrieval happen atomically.
	query := `
		INSERT INTO olc_alert_sequence (repository_id, number, created_at, updated_at) 
		VALUES (?, ?, ?, ?)
		ON DUPLICATE KEY UPDATE
			number = LAST_INSERT_ID(number + ?),
			updated_at = ?
	`
	timestamp := time.Now()
	result, err := g.db.ExecContext(ctx, query, repositoryID, count, timestamp, timestamp, count, timestamp)
	if err != nil {
		return 0, fmt.Errorf("failed to get next number in the sequence: %w", err)
	}

	rows, err := result.RowsAffected()
	if err != nil {
		return 0, fmt.Errorf("failed to get rows affected: %w", err)
	}

	switch rows {
	case 1:
		// New repository: INSERT operation created a new row.
		// The initial sequence number was set to 'count' (1).
		return 1, nil
	case 2:
		// Existing repository: UPDATE operation incremented the sequence.
		// Use LAST_INSERT_ID() to get the new sequence value that was set during UPDATE.
		id, err := result.LastInsertId()
		if err != nil {
			return 0, fmt.Errorf("failed to fetch last insert id: %w", err)
		}

		// The LastInsertId() returns the new sequence value.
		// We want to return the next available alert number, which is (new sequence value) - count + 1.
		// This is useful in cases where sequence is incremented by more than 1.

		if id < 0 || id > math.MaxUint32 {
			// Guard against integer overflow during int64->uint32 conversion.
			// Realistically impossible (would require 4+ billion alerts per repository),
			// but we need to make the linter happy.
			return 0, fmt.Errorf("sequence value %d is out of range for uint32", id)
		}
		return uint32(id) - count + 1, nil
	default:
		// Unexpected case: MySQL should only return 1 (INSERT) or 2 (UPDATE) rows affected.
		return 0, errors.New("updating sequence updated unexpected number of rows")
	}
}

// NullGenerator provides an in-memory sequence generator for testing.
type NullGenerator struct {
	current uint32
}

// NewNullGenerator implements a null sequence generator.
func NewNullGenerator() *NullGenerator {
	return &NullGenerator{}
}

// Next returns the next sequential number, incrementing an internal counter.
func (n *NullGenerator) Next(_ context.Context, _ uint64) (uint32, error) {
	n.current++
	return n.current, nil
}

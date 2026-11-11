// Package db provides database storage implementation for configuration data.
package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/github/configsd/internal/model"
	"github.com/github/go-dbkit"
	stats "github.com/github/go-stats"
	"github.com/jmoiron/sqlx"
)

// SQLStore implements the Store interface using a SQL database.
type SQLStore struct {
	db      *sqlx.DB
	retrier *dbkit.DBRetrierx
}

var _ model.Store = (*SQLStore)(nil)

// NewDbConnectionFromEnvironment creates a new database connection using environment configuration.
func NewDbConnectionFromEnvironment() (*sqlx.DB, error) {
	connConfig, err := dbkit.NewConfigFromEnvironment()
	if err != nil {
		return nil, fmt.Errorf("failed to load database configuration: %w", err)
	}

	configClusterConfig, err := connConfig.DBConfigFor("configurations")
	if err != nil {
		return nil, fmt.Errorf("failed to get config cluster config: %w", err)
	}

	conn, err := dbkit.ConnectWithDefaultAnnotations(configClusterConfig, "configsd")
	if err != nil {
		return nil, fmt.Errorf("error connecting to database: %w", err)
	}

	return dbkit.OpenWithDefaultOTELX(configClusterConfig, conn), nil
}

// NewStore creates a new SQLStore instance with the given database connection and stats client.
func NewStore(dbConn *sqlx.DB, statsClient stats.Client) (*SQLStore, error) {
	return &SQLStore{
		db:      dbConn,
		retrier: dbkit.NewDefaultDBRetrierx(dbConn, statsClient),
	}, nil
}

// ConfigurationEntry represents a configuration entry from the database.
type ConfigurationEntry struct {
	Name       string    `db:"name"`
	Value      string    `db:"value"`
	Final      bool      `db:"final"`
	TargetType string    `db:"target_type"`
	TargetID   uint64    `db:"target_id"`
	CreatedAt  time.Time `db:"created_at"`
	UpdatedAt  time.Time `db:"updated_at"`
	Priority   *int      `db:"priority"`
}

// targetTypeForDB converts a TargetType to the database format.
// The database uses lowercase 'global' for historical reasons, while the model uses 'Global'.
func targetTypeForDB(t model.TargetType) string {
	if t == model.Global {
		return "global"
	}
	return string(t)
}

// targetTypeFromDB converts a database target_type value to the model TargetType.
// The database uses lowercase 'global' for historical reasons, while the model uses 'Global'.
func targetTypeFromDB(dbType string) model.TargetType {
	if dbType == "global" {
		return model.Global
	}
	return model.TargetType(dbType)
}

// SetRepositoryOwner implements model.Store.
func (c *SQLStore) SetRepositoryOwner(ctx context.Context, repoID, ownerID uint64) error {
	if repoID == 0 {
		return errors.New("invalid repository ID: cannot be zero")
	}
	if ownerID == 0 {
		return errors.New("invalid owner ID: cannot be zero")
	}

	return c.retrier.WithRetries(ctx, false, func(ctx context.Context) error {
		now := time.Now().UTC()
		_, err := c.db.ExecContext(ctx, `
			REPLACE INTO repository_owners (repository_id, resource_owner_id, updated_at)
			VALUES (?, ?, ?)
		`, repoID, ownerID, now)
		return err
	})
}

// AllProperties retrieves all configuration entries for the given target with hierarchical resolution.
// For business targets, it returns both business-specific and global entries, with business taking precedence.
// For global targets, it returns only global entries.
func (c *SQLStore) AllProperties(ctx context.Context, target model.ConfigurationTarget) (map[string]model.Configuration, error) {
	// Build the list of targets to query based on hierarchy
	var targets []model.ConfigurationTarget
	if target.Type == model.Business {
		// For business targets, include both the specific business and global fallbacks
		targets = append(targets, target, model.GlobalTarget)
	} else {
		// For all other target types, query only the specific target
		targets = append(targets, target)
	}

	params := []interface{}{}

	baseQuery := `SELECT name, value, final, target_type, target_id, created_at, updated_at,
          CASE target_type
          WHEN 'global'               THEN 0
          WHEN 'Business'             THEN 1
          END AS priority
          FROM configuration_entries
          WHERE (
            %s
          )
          ORDER BY priority`

	// Build target query segment
	targetQueries := []string{}
	for _, t := range targets {
		targetQueries = append(targetQueries, "(target_type=? AND target_id=?)")
		params = append(params, targetTypeForDB(t.Type), t.ID)
	}

	rows, err := c.retrier.Queryx(ctx, fmt.Sprintf(baseQuery, strings.Join(targetQueries, " OR ")), params...)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return make(map[string]model.Configuration), nil
		}
		return nil, fmt.Errorf("finding configuration entries: %w", err)
	}
	defer rows.Close()

	return c.rowsToEntries(ctx, rows)
}

// ResolvedConfigsByTargetWithOwners retrieves all configuration entries for the given targets.
func (c *SQLStore) ResolvedConfigsByTargetWithOwners(ctx context.Context, targets []model.ConfigurationTarget) (map[string]model.Configuration, error) {
	// Build the list of target queries
	var targetQueries []string
	var params []interface{}
	for _, target := range targets {
		targetQueries = append(targetQueries, "(target_type=? AND target_id=?)")
		params = append(params, targetTypeForDB(target.Type), target.ID)
	}

	baseQuery := `SELECT name, value, final, target_type, target_id, created_at, updated_at,
          CASE target_type
          WHEN 'global'               THEN 0
          WHEN 'Business'             THEN 1
          WHEN 'User'                 THEN 2
          WHEN 'Repository'           THEN 3
          END AS priority
          FROM configuration_entries
          WHERE (
            %s
          )
          ORDER BY priority ASC`

	rows, err := c.retrier.Queryx(ctx, fmt.Sprintf(baseQuery, strings.Join(targetQueries, " OR ")), params...)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return make(map[string]model.Configuration), nil
		}
		return nil, fmt.Errorf("finding configuration entries: %w", err)
	}
	defer rows.Close()

	return c.rowsToEntries(ctx, rows)
}

// rowsToEntries converts database rows to a map of configuration entries.
// Processes rows in priority order and skips entries marked as final once found.
func (c *SQLStore) rowsToEntries(ctx context.Context, rows *sqlx.Rows) (map[string]model.Configuration, error) {
	entries := make(map[string]model.Configuration)
	err := c.retrier.WithRetries(
		ctx,
		false,
		func(ctx context.Context) error {
			for {
				if !rows.Next() {
					if rows.Err() != nil {
						return rows.Err()
					}
					break
				}

				var entry ConfigurationEntry
				if err := rows.StructScan(&entry); err != nil {
					return err
				}

				current, ok := entries[entry.Name]
				if ok && current.Final {
					// Already found a final entry, skip additional rows
					continue
				}

				entryTarget := &model.ConfigurationTarget{
					Type: targetTypeFromDB(entry.TargetType),
					ID:   entry.TargetID,
				}

				entries[entry.Name] = model.Configuration{
					Name:      entry.Name,
					Value:     entry.Value,
					Target:    entryTarget,
					Final:     entry.Final,
					CreatedAt: entry.CreatedAt,
					UpdatedAt: entry.UpdatedAt,
				}
			}
			return nil
		},
	)
	if err != nil {
		return nil, fmt.Errorf("retrieving configuration entries: %w", err)
	}

	return entries, nil
}

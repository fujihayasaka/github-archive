package main

import (
	"context"
	"database/sql"
	"fmt"
)

type serviceName string

const (
	serviceDeployer serviceName = "deployer"
	servicePayloads serviceName = "payloads"
)

var truncatorTableMap = map[serviceName][]string{
	serviceDeployer: {
		"azp_resources",
		"workflow_builds",
		"workflow_build_executions",
		"workflow_jobs",
		"workflow_schedules",
	},
	servicePayloads: {
		"payloads",
	},
}

type truncator struct {
	db      *sql.DB
	service serviceName
}

func (t *truncator) truncate(ctx context.Context, dryRun bool) error {
	tables, ok := truncatorTableMap[t.service]
	if !ok {
		return fmt.Errorf("Could not find table list for service: %s", t.service)
	}

	for _, table := range tables {
		row := t.db.QueryRowContext(ctx, fmt.Sprintf("SELECT count(*) FROM %s LIMIT 1", table))

		var count int64
		if err := row.Scan(&count); err != nil {
			return fmt.Errorf("Could not parse row count in result from %s: %w", table, err)
		}

		if dryRun {
			fmt.Printf("Would delete %d rows from %s\n", count, table)
			continue
		}

		fmt.Printf("Truncating %s, deleting %d rows\n", table, count)

		_, err := t.db.ExecContext(ctx, fmt.Sprintf("TRUNCATE %s", table))
		if err != nil {
			return fmt.Errorf("Error truncating %s: %w", table, err)
		}
	}

	return nil
}

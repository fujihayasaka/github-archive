package migrations

import (
	"context"

	"github.com/github/turboscan/ts/mysql/upgrades"
)

// language=SQL
const toolVersionIDSQL = `SELECT tv0.id
FROM ts_tools AS t0
INNER JOIN ts_tool_versions AS tv0 ON tv0.tool_id = t0.id
WHERE t0.repository_id = 0
	AND t0.canonical_name = tX.canonical_name
	AND tv0.name <=> tvX.name
	AND tv0.full_name <=> tvX.full_name
	AND tv0.version <=> tvX.version
	AND tv0.semantic_version <=> tvX.semantic_version
ORDER BY t0.id, tv0.id ASC
LIMIT 1`

// LocalToGlobalToolsAndRules rewires all references to local rules and tools to their global counterparts.
// This runs per-analysis to ensure that the data is left in a consistent state as each partition completes.
// As a convention during this transition, tables that are suffixed with 0 refer to global rows (e.g: r0 - global rules)
// tables that are suffixed with X refer to local rows (e.g: rX - local rules).
var _ = Transitions.Step(100).Function("ts_analyses", func(ctx context.Context, db upgrades.DB, start, end uint64) error {
	var err error

	for _, table := range []string{"ts_physical_alerts", "ts_analysis_rules", "ts_metric_results"} {
		// update the rule_id key on the target table to point to the new global rules
		_, err = db.ExecContext(ctx,
			// language=SQL
			`UPDATE `+table+` AS target
			INNER JOIN ts_rules AS rX ON target.rule_id = rX.id AND rX.repository_id = target.repository_id
			INNER JOIN ts_tools AS tX ON tX.id = rX.tool_id
			INNER JOIN ts_analyses FORCE INDEX(PRIMARY) ON ts_analyses.id = target.analysis_id AND target.repository_id = ts_analyses.repository_id
			SET target.rule_id = (
				SELECT r0.id
				FROM ts_rules AS r0
				INNER JOIN ts_tools AS t0 ON t0.repository_id = 0 AND r0.tool_id = t0.id
				WHERE r0.repository_id = 0
				AND t0.canonical_name = tX.canonical_name
				AND r0.hash = rX.hash
				AND r0.sarif_identifier = rX.sarif_identifier
				ORDER BY r0.tool_id ASC
				LIMIT 1
			)
			WHERE ts_analyses.id BETWEEN ? AND ?`,
			start, end,
		)
		if err != nil {
			return err
		}
	}

	// update all analyses to use global tools
	_, err = db.ExecContext(ctx, `
		UPDATE ts_analyses AS target
		INNER JOIN ts_tools AS tX ON tX.id = target.tool_id AND tX.repository_id = target.repository_id
		SET target.tool_id = (
		    SELECT MIN(t0.id)
		    FROM ts_tools AS t0
		    WHERE t0.repository_id = 0 AND tX.canonical_name = t0.canonical_name
		)
		WHERE target.id BETWEEN ? AND ?`,
		start, end,
	)
	if err != nil {
		return err
	}

	_, err = db.ExecContext(ctx,
		// language=SQL
		`UPDATE ts_analyses AS target
		INNER JOIN ts_tool_versions AS tvX ON tvX.id = target.tool_version_id AND tvX.repository_id = target.repository_id
		INNER JOIN ts_tools AS tX ON tvX.tool_id = tX.id AND tX.repository_id = tvX.repository_id
		SET target.tool_version_id = (`+toolVersionIDSQL+`)
		WHERE target.id BETWEEN ? AND ?`,
		start, end,
	)
	if err != nil {
		return err
	}

	for _, table := range []string{"ts_analysis_tool_versions", "ts_timeline_events"} {
		// update all tables to use global tools
		_, err = db.ExecContext(ctx,
			// language=SQL
			`UPDATE `+table+` AS target
			INNER JOIN ts_tool_versions AS tvX ON tvX.id = target.tool_version_id AND tvX.repository_id = target.repository_id
			INNER JOIN ts_tools AS tX ON tvX.tool_id = tX.id AND tX.repository_id = tvX.repository_id
			INNER JOIN ts_analyses ON ts_analyses.id = target.analysis_id AND target.repository_id = ts_analyses.repository_id
			SET target.tool_version_id = (`+toolVersionIDSQL+`)
			WHERE ts_analyses.id BETWEEN ? AND ?`,
			start, end,
		)
		if err != nil {
			return err
		}
	}

	_, err = db.ExecContext(ctx,
		// language=SQL
		`UPDATE ts_analysis_rules AS target
		INNER JOIN ts_tool_versions AS tvX ON tvX.id = target.defining_tool_version_id AND tvX.repository_id = target.repository_id
		INNER JOIN ts_tools AS tX ON tvX.tool_id = tX.id AND tX.repository_id = tvX.repository_id
		INNER JOIN ts_analyses ON ts_analyses.id = target.analysis_id AND target.repository_id = ts_analyses.repository_id
		SET target.defining_tool_version_id = (`+toolVersionIDSQL+`)
		WHERE ts_analyses.id BETWEEN ? AND ?`,
		start, end,
	)
	return err
})

package migrations

import (
	"context"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mysql/upgrades"
)

var _ = Transitions.Step(1000).Function("ts_analyses", func(ctx context.Context, db upgrades.DB, start, end uint64) error {
	rows, err := db.QueryContext(ctx, "SELECT id, repository_id, tool_id, ref_bytes, analysis_category FROM ts_analyses FORCE INDEX(PRIMARY) WHERE id BETWEEN ? AND ? AND configuration_id = 0", start, end)
	if err != nil {
		return err
	}
	defer func() {
		innerErr := rows.Close()
		if err == nil {
			err = innerErr
		}
	}()

	configurations := map[ts.AnalysisID]ts.Configuration{}

	for rows.Next() {
		if rows.Err() != nil {
			return err
		}

		var id, repositoryID, toolID uint64
		var refBytes []byte
		var analysisCategory string
		if err := rows.Scan(&id, &repositoryID, &toolID, &refBytes, &analysisCategory); err != nil {
			return err
		}

		configuration := ts.Configuration{
			RepositoryID: ts.RepositoryEID(repositoryID),
			Ref:          refBytes,
			ToolID:       ts.ToolID(toolID),
			Category:     ts.Category(analysisCategory),
		}
		configuration.UpdateHash()

		configurations[ts.AnalysisID(id)] = configuration
	}

	createStatement := "INSERT INTO ts_configurations (created_at, updated_at, repository_id, ref, tool_id, category, hash) VALUES "
	createValues := []interface{}{}
	first := true
	for _, configuration := range configurations {
		now := sqltime.Now()
		if !first {
			createStatement += ","
		}
		first = false
		createStatement += "(?,?,?,?,?,?,?)"
		createValues = append(createValues, now, now, configuration.RepositoryID, configuration.Ref, configuration.ToolID, configuration.Category, configuration.Hash)
	}
	createStatement += " ON DUPLICATE KEY UPDATE hash=hash"

	if len(createValues) == 0 {
		return nil
	}
	_, err = db.ExecContext(ctx, createStatement, createValues...)
	if err != nil {
		return err
	}

	updateStatement := "UPDATE ts_analyses SET configuration_id = CASE id "
	updateValues := []interface{}{}
	for id, configuration := range configurations {
		updateStatement += "WHEN ? THEN (SELECT id FROM ts_configurations WHERE repository_id = ? AND hash = ?)"
		updateValues = append(updateValues, id, configuration.RepositoryID, configuration.Hash)
	}
	updateStatement += " END WHERE id IN ("
	first = true
	for id := range configurations {
		if !first {
			updateStatement += ","
		}
		first = false
		updateStatement += "?"
		updateValues = append(updateValues, id)
	}
	updateStatement += ")"
	_, err = db.ExecContext(ctx, updateStatement, updateValues...)
	return err
})

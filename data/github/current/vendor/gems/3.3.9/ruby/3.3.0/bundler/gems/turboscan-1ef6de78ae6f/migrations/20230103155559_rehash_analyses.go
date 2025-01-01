package migrations

import (
	"context"
	"crypto/sha256"
	"encoding/binary"

	"github.com/github/turboscan/ts/mysql/upgrades"
)

var _ = Transitions.Step(1000).Function("ts_analyses", func(ctx context.Context, db upgrades.DB, start, end uint64) error {
	rows, err := db.QueryContext(ctx, "SELECT id, repository_id, tool_id, ref_bytes, analysis_category FROM ts_analyses FORCE INDEX(PRIMARY) WHERE id BETWEEN ? AND ? AND configuration_hash_bytes IS NULL", start, end)
	if err != nil {
		return err
	}
	defer func() {
		innerErr := rows.Close()
		if err == nil {
			err = innerErr
		}
	}()

	newHashes := map[uint64][]byte{}

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

		hash := sha256.New()
		buf := make([]byte, 8)
		binary.BigEndian.PutUint64(buf, repositoryID)
		hash.Write(buf)
		binary.BigEndian.PutUint64(buf, toolID)
		hash.Write(buf)
		hash.Write(refBytes)
		hash.Write([]byte(analysisCategory))
		bytes := hash.Sum(nil)

		newHashes[id] = bytes
	}

	updateStatement := "INSERT INTO ts_analyses (id, configuration_hash_bytes) VALUES "
	updateValues := []interface{}{}
	first := true
	for id, hash := range newHashes {
		if !first {
			updateStatement += ","
		}
		first = false
		updateStatement += "(?,?)"
		updateValues = append(updateValues, id, hash)
	}
	updateStatement += " ON DUPLICATE KEY UPDATE configuration_hash_bytes = VALUES(configuration_hash_bytes)"

	if len(updateValues) > 0 {
		_, err = db.ExecContext(ctx, updateStatement, updateValues...)
	}
	return err
})

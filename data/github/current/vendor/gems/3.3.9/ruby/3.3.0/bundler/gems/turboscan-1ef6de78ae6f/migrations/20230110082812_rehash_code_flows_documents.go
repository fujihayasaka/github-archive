package migrations

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/github/turboscan/ts/mysql/upgrades"
	"github.com/gowebpki/jcs"
	"github.com/pkg/errors"
)

var _ = Transitions.Step(1000).Function(
	"ts_code_flows_documents",
	func(ctx context.Context, db upgrades.DB, start, end uint64) error {
		rows, err := db.QueryContext(ctx, "SELECT id, document FROM ts_code_flows_documents FORCE INDEX(PRIMARY) WHERE id BETWEEN ? AND ? AND document_hash IS NULL", start, end)
		if err != nil {
			return err
		}
		defer func() {
			innerErr := rows.Close()
			if err == nil {
				err = innerErr
			}
		}()

		hashes := make(map[uint64][]byte, end-start)

		for rows.Next() {
			if rows.Err() != nil {
				return err
			}
			var id uint64
			var document json.RawMessage
			if err := rows.Scan(&id, &document); err != nil {
				return err
			}
			document, err := jcs.Transform(document)
			if err != nil {
				return errors.Wrap(err, "failed to normalize json document")
			}
			hash := sha256.Sum256(document)
			hashes[id] = hash[:]
		}

		if len(hashes) == 0 {
			return nil
		}

		cases := make([]any, 0, len(hashes)*2)

		for id, hash := range hashes {
			cases = append(cases, id, hash)
		}

		query := fmt.Sprintf(`
UPDATE ts_code_flows_documents
SET document_hash = CASE id %[1]s END
WHERE id BETWEEN ? AND ?
AND document_hash IS NULL`,
			strings.Repeat("\nWHEN ? THEN ?", len(hashes)),
		)

		if _, err := db.ExecContext(ctx, query, append(cases, start, end)...); err != nil {
			return err
		}
		return nil
	})

package migrate

// copied from https://github.com/github/hookshot-go/blob/master/internal/schema/transitions.go

import (
	"database/sql"

	"github.com/github/go-dbmigrator"
)

// GetTransitions returns all transitions to be applied to the database
func GetTransitions(db *sql.DB, driver string) (*dbmigrator.Transitioner, error) {
	trans := dbmigrator.NewTransitioner()

	//nolint:gocritic // Commented out code is an example of how to add a transition
	// EXAMPLE:
	//
	// dbConn := sqlx.NewDb(db, driver)
	//
	// // As we create transitions, tie them to the version number of the
	// // corresponding migration's version number and register them.
	// //
	// // The following is a transition that populates the parent column on the
	// // webhook_payloads table from the parent_type and parent_id columns on the table.
	// // This will run subsequent to the migration that renames the table and adds the column.
	// err := trans.Add(20201201160347, func(ctx context.Context) error {
	// 	return transitions.PopulateParentsInPayloadsTableWithRetries(ctx, dbConn, 10000)
	// })
	// if err != nil {
	// 	return nil, err
	// }

	return trans, nil
}

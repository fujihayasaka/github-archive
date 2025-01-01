package sequence

import (
	"github.com/pkg/errors"

	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/sequence/memory"
	"github.com/github/turboscan/ts/sequence/mysql"
	"github.com/jinzhu/gorm"
)

// CreatorFunc is the function that will generate a new
// sequence implementation.
type CreatorFunc func(repoID uint64) Sequence

// NewMySQLSequenceCreator will create a function
// to generate new sequences backed by the database
// Note that we receive the database connection here, and we
// ensure that is not a transaction, the reason is that we should
// not generate sequences inside a transaction for less DB contention
func NewMySQLSequenceCreator(db *gorm.DB, tableName string) (CreatorFunc, error) {
	sDb := gormext.GetDB(db)
	if sDb == nil {
		return nil, errors.New("the mysql sequence creator needs to receive a DB connection, received nil or something else(i.e.: transaction)")
	}

	return func(repoID uint64) Sequence {
		return mysql.New(tableName, repoID, sDb)
	}, nil
}

// NewMemorySequenceCreator will return a function
// that creates a new memory sequence every time it
// is requested. Used on tests
func NewMemorySequenceCreator() CreatorFunc {
	sequences := make(map[uint64]*memory.MemorySequence)

	return func(repoID uint64) Sequence {
		v := sequences[repoID]
		if v == nil {
			v = &memory.MemorySequence{}
			sequences[repoID] = v
		}
		return v
	}
}

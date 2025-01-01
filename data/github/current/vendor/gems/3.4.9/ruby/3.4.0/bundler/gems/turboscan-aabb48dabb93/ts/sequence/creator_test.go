package sequence

import (
	"testing"

	"github.com/github/turboscan/ts/dbtest"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func TestMySQLSequenceCreator(t *testing.T) {
	db := dbtest.RequireConnection(t)

	err := db.Transaction(func(tx *gorm.DB) error {
		_, err := NewMySQLSequenceCreator(tx, "foo")
		return err
	})
	require.Error(t, err, "errors when inside a transaction")

}

func TestNewMemorySequenceCreator(t *testing.T) {
	creatorFunc := NewMemorySequenceCreator()
	seq := creatorFunc(1)
	require.NotNil(t, seq)

	seq1 := creatorFunc(1)
	seq2 := creatorFunc(2)

	require.True(t, seq == seq1)
	require.True(t, seq1 != seq2)
}

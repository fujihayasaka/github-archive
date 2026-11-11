package sequence_test

import (
	"database/sql"
	"fmt"
	"os"
	"testing"

	"github.com/github/osslicensecompliance/internal/storage/sequence"
	"github.com/github/osslicensecompliance/internal/storage/testmysql"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newTestSequenceGenerator(t *testing.T) (sequence.Generator, error) {
	t.Helper()
	testDB, err := testmysql.NewTestDB("../../../schemas")
	require.NoError(t, err)
	t.Cleanup(func() { testDB.Close() })

	db, err := sql.Open("mysql", fmt.Sprintf("%s?parseTime=true", testDB.ConnectionString))
	if err != nil {
		return nil, err
	}
	t.Cleanup(func() {
		err = db.Close()
		if err != nil {
			t.Errorf("failed to close database connection: %v", err)
		}
	})

	return sequence.NewMySQLGenerator(db), nil
}

func TestSequenceGenerator_FirstCallReturnsOne(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	gen, _ := newTestSequenceGenerator(t)
	ctx := t.Context()
	repositoryID := uint64(12345)

	number, err := gen.Next(ctx, repositoryID)

	require.NoError(t, err)
	assert.Equal(t, uint32(1), number, "First call should return 1")
}

func TestSequenceGenerator_DifferentRepositoriesHaveIndependentSequences(t *testing.T) {
	if os.Getenv("CI") != "true" {
		t.Skip("Only run in CI")
	}
	gen, _ := newTestSequenceGenerator(t)
	ctx := t.Context()
	repo1 := uint64(12345)
	repo2 := uint64(67890)

	// Get numbers for repo1
	number1_1, err := gen.Next(ctx, repo1)
	require.NoError(t, err)
	assert.Equal(t, uint32(1), number1_1)

	number1_2, err := gen.Next(ctx, repo1)
	require.NoError(t, err)
	assert.Equal(t, uint32(2), number1_2)

	// Get numbers for repo2 (should start from 1)
	number2_1, err := gen.Next(ctx, repo2)
	require.NoError(t, err)
	assert.Equal(t, uint32(1), number2_1)

	// Get another number for repo1 (should continue from 2)
	number1_3, err := gen.Next(ctx, repo1)
	require.NoError(t, err)
	assert.Equal(t, uint32(3), number1_3)

	// Get another number for repo2 (should continue from 1)
	number2_2, err := gen.Next(ctx, repo2)
	require.NoError(t, err)
	assert.Equal(t, uint32(2), number2_2)
}

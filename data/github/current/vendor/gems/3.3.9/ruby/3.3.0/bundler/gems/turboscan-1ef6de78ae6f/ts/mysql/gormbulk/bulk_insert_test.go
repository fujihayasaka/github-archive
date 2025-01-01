package gormbulk

import (
	"testing"

	"github.com/github/turboscan/ts"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts/dbtest"
)

func TestSetIDs(t *testing.T) {
	db := dbtest.RequireConnection(t)

	{
		inc, err := GetAutoIncrementIncrement(db)
		require.NoError(t, err)
		require.Equal(t, int64(1), inc)
	}

	{
		inc, err := GetAutoIncrementIncrement(db)
		require.NoError(t, err)
		require.Equal(t, int64(1), inc)
	}

	{
		var analyses []*ts.Analysis
		require.NoError(t, setIDs(db, 1, analyses, 5))
	}

	{
		analyses := []*ts.Analysis{{}}
		require.NoError(t, setIDs(db, 1, analyses, 5))
		require.Equal(t, ts.AnalysisID(1), analyses[0].ID)
	}

	{
		analyses := []*ts.Analysis{{}}
		require.NoError(t, setIDs(db, 1, analyses, 5))
		require.Equal(t, ts.AnalysisID(1), analyses[0].ID)
	}

	{
		analyses := []*ts.Analysis{{}, {}, {}}
		require.NoError(t, setIDs(db, 1, analyses, 5))
		require.Equal(t, ts.AnalysisID(1), analyses[0].ID)
		require.Equal(t, ts.AnalysisID(6), analyses[1].ID)
		require.Equal(t, ts.AnalysisID(11), analyses[2].ID)
	}

	{
		analyses := []*ts.Analysis{{}, {}, {}}
		require.NoError(t, setIDs(db, 1, analyses, 1))
		require.Equal(t, ts.AnalysisID(1), analyses[0].ID)
		require.Equal(t, ts.AnalysisID(2), analyses[1].ID)
		require.Equal(t, ts.AnalysisID(3), analyses[2].ID)
	}
}

// NOTE: Using a _test package lets us use helpers without an import cycle.
package gitaccess_test

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_RepoDiffBlobOIDChanges(t *testing.T) {
	var (
		repoA = types.RepoID(1)
		repoB = types.RepoID(2)
	)

	diff := gitaccess.RepoDiff{
		repoA: []*gitaccess.DiffEntry{
			{
				Path:   "modified-path",
				OID:    helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
				Change: gitaccess.Delete,
			},
			{
				Path:   "deleted-path",
				OID:    helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
				Change: gitaccess.Delete,
			},
		},
		repoB: []*gitaccess.DiffEntry{
			{
				Path:   "modified-path",
				OID:    helpers.OID(t, "cccccccccccccccccccccccccccccccccccccccc"),
				Change: gitaccess.Add,
			},
			{
				Path:   "new-path",
				OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
				Change: gitaccess.Add,
			},
			{
				Path:   "new-path-duplicate",
				OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
				Change: gitaccess.Add,
			},
		},
	}

	expected := []*gitaccess.BlobOIDChange{
		{
			ObjectID:      helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "modified-path", Change: gitaccess.Delete}},
		},
		{
			ObjectID:      helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "deleted-path", Change: gitaccess.Delete}},
		},
		{
			ObjectID:      helpers.OID(t, "cccccccccccccccccccccccccccccccccccccccc"),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "modified-path", Change: gitaccess.Add}},
		},
		{
			ObjectID:      helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
			BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "new-path", Change: gitaccess.Add}, {Path: "new-path-duplicate", Change: gitaccess.Add}},
		},
	}

	require.ElementsMatch(t, expected, diff.BlobOIDChanges())
}

func Test_RepoDiff_Filter(t *testing.T) {
	var (
		repoA = types.RepoID(1)
		repoB = types.RepoID(2)
	)
	diff := gitaccess.RepoDiff{
		repoA: []*gitaccess.DiffEntry{
			{
				Path:   "modified-path",
				OID:    helpers.OID(t, "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
				Change: gitaccess.Delete,
			},
			{
				Path:   "deleted-path",
				OID:    helpers.OID(t, "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
				Change: gitaccess.Delete,
			},
		},
		repoB: []*gitaccess.DiffEntry{
			{
				Path:   "modified-path",
				OID:    helpers.OID(t, "cccccccccccccccccccccccccccccccccccccccc"),
				Change: gitaccess.Add,
			},
			{
				Path:   "new-path",
				OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
				Change: gitaccess.Add,
			},
			{
				Path:   "new-path-duplicate",
				OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
				Change: gitaccess.Add,
			},
		},
	}

	// These represent the missing OIDs. Filter should remove everything except them.
	oids := map[gitaccess.ObjectID]bool{
		helpers.OID(t, "cccccccccccccccccccccccccccccccccccccccc"): true,
		helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"): true,
	}
	filteredDiff := diff.Filter(oids)

	expected := gitaccess.RepoDiff{
		repoA: []*gitaccess.DiffEntry{},
		repoB: []*gitaccess.DiffEntry{
			{
				Path:   "modified-path",
				OID:    helpers.OID(t, "cccccccccccccccccccccccccccccccccccccccc"),
				Change: gitaccess.Add,
			},
			{
				Path:   "new-path",
				OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
				Change: gitaccess.Add,
			},
			{
				Path:   "new-path-duplicate",
				OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
				Change: gitaccess.Add,
			},
		},
	}

	require.Empty(t, filteredDiff[repoA], "filtered diff should remove everything under repoA: %+v", filteredDiff[repoA])
	require.ElementsMatch(t, expected[repoB], filteredDiff[repoB])
}

package healthcheck

import (
	"testing"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/github/blackbird/crates/core/pkg/shard"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_contentTrackerHybridSharding(t *testing.T) {
	var (
		oid1 = helpers.OIDFromContent(t, "aaa")
		oid2 = helpers.OIDFromContent(t, "bbb")
		oid3 = helpers.OIDFromContent(t, "ccc")
	)
	opm := newContentTracker(epoch.EpochModeLegacyHybrid)
	opm.add(oid1, "a.txt")
	opm.add(oid1, "b.txt")
	opm.add(oid1, "c.txt")
	opm.add(oid2, "d.txt")
	opm.add(oid3, "e.txt")

	require.ElementsMatch(t, []string{"a.txt", "b.txt", "c.txt"}, opm.pathsForBlobSHA(oid1))

	require.False(
		t,
		opm.removePathForBlobSHA(helpers.OIDFromContent(t, "not in the map"), "path.txt"),
		"removing a blob path for OID that isn't there is not an error",
	)
	require.False(t, opm.removePathForBlobSHA(oid1, "not-there.txt"), "removing a path that isn't there is not an error")

	require.Equal(t, 3, opm.numDocs())
	require.Equal(t, 5, opm.numPaths())
	require.Equal(t, map[gitaccess.ObjectID]bool{oid1: true, oid2: true, oid3: true}, opm.blobSHAs())

	removed := opm.removePathForBlobSHA(oid3, "e.txt")

	require.True(t, removed)
	require.Equal(t, 2, opm.numDocs())
	require.Equal(t, 4, opm.numPaths())

	opm.removeDocSHA(oid1)

	require.Equal(t, 1, opm.numDocs())
	require.Equal(t, 1, opm.numPaths())

	require.Equal(t, map[gitaccess.ObjectID]bool{oid2: true}, opm.blobSHAs())
	require.Empty(t, opm.pathsForBlobSHA(oid1))
	require.Empty(t, opm.pathsForBlobSHA(oid3))
	require.ElementsMatch(t, []string{"d.txt"}, opm.pathsForBlobSHA(oid2))
}

func Test_contentTrackerEmbeddingSharding(t *testing.T) {
	var (
		oid1 = helpers.OIDFromContent(t, "aaa")
		oid2 = helpers.OIDFromContent(t, "bbb")
		oid3 = helpers.OIDFromContent(t, "ccc")
	)
	opm := newContentTracker(epoch.EpochModeEmbeddings)
	opm.add(oid1, "a.txt")
	opm.add(oid1, "b.txt")
	opm.add(oid1, "c.txt")
	opm.add(oid2, "d.txt")
	opm.add(oid3, "e.txt")

	require.ElementsMatch(t, []string{"a.txt", "b.txt", "c.txt"}, opm.pathsForBlobSHA(oid1))

	require.False(
		t,
		opm.removePathForBlobSHA(helpers.OIDFromContent(t, "not in the map"), "path.txt"),
		"removing a blob path for OID that isn't there is not an error",
	)
	require.False(t, opm.removePathForBlobSHA(oid1, "not-there.txt"), "removing a path that isn't there is not an error")

	require.Equal(t, 5, opm.numDocs())
	require.Equal(t, 5, opm.numPaths())
	require.Equal(t, map[gitaccess.ObjectID]bool{oid1: true, oid2: true, oid3: true}, opm.blobSHAs())

	removed := opm.removePathForBlobSHA(oid3, "e.txt")

	require.True(t, removed)
	require.Equal(t, 4, opm.numDocs())
	require.Equal(t, 4, opm.numPaths())

	opm.removeDocSHA(gitaccess.NewObjectIDFromBytes(shard.DocSHAForEpochMode(oid1.Bytes(), "a.txt", epoch.EpochModeEmbeddings)))

	require.Equal(t, 3, opm.numDocs())
	require.Equal(t, 3, opm.numPaths())

	require.Equal(t, map[gitaccess.ObjectID]bool{oid1: true, oid2: true}, opm.blobSHAs())
	require.ElementsMatch(t, []string{"b.txt", "c.txt"}, opm.pathsForBlobSHA(oid1))
	require.ElementsMatch(t, []string{"d.txt"}, opm.pathsForBlobSHA(oid2))
}

func Test_contentTrackerInvariants(t *testing.T) {
	opm := newContentTracker(epoch.EpochModeLegacyHybrid)

	require.Panics(
		t,
		func() { opm.removeDocSHA(helpers.OIDFromContent(t, "not in the map")) },
		"removing an non-existent OID should panic",
	)

	// Manually invalidate the contentTracker by not setting docSHAToPaths
	opm = newContentTracker(epoch.EpochModeLegacyHybrid)
	oid := helpers.UniqueOID(t)
	opm.pathToDocSHA["path.txt"] = oid
	require.Panics(
		t,
		func() { opm.removePathForBlobSHA(oid, "path.txt") },
		"removing an OID with a path not in the pathMap should panic",
	)
}

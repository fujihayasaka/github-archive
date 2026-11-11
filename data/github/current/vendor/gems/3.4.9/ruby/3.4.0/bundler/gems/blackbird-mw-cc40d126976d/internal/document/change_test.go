package document

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/github/blackbird/crates/core/pkg/epoch"
	blackbird "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/messages"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_NewGitDocumentFromContent(t *testing.T) {
	msg := messages.Ingest{
		RepoID:          123,
		OwnerID:         456,
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}

	var tests = []struct {
		name    string
		mode    epoch.EpochMode // default: hybrid
		blob    *gitaccess.BlobContentChange
		error   bool
		message string
	}{
		{
			name: "happy path",
			blob: &gitaccess.BlobContentChange{
				ObjectID: helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:  []byte("hello world"),
				BlobLocations: []*gitaccess.BlobLocationEntry{
					{
						Path:   "foo/bar.txt",
						Change: gitaccess.Add,
					},
				},
			},
		},
		{
			name: "all Delete locations requires content",
			blob: &gitaccess.BlobContentChange{
				ObjectID: helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				BlobLocations: []*gitaccess.BlobLocationEntry{
					{
						Path:   "foo/deleted.txt",
						Change: gitaccess.Delete,
					},
				},
			},
			error:   true,
			message: "cannot create document less than 3 bytes (got 0)",
		},
		{
			name: "with Add locations must have content",
			blob: &gitaccess.BlobContentChange{
				ObjectID: helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				BlobLocations: []*gitaccess.BlobLocationEntry{
					{
						Path:   "foo/deleted.txt",
						Change: gitaccess.Delete,
					},
					{
						Path:   "foo/added.txt",
						Change: gitaccess.Add,
					},
				},
			},
			error:   true,
			message: "document less than",
		},
		{
			name: "less than 3 bytes of content",
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("hi"),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "foo/bar.txt", Change: gitaccess.Add}},
			},
			error:   true,
			message: "document less than",
		},
		{
			name: "more than max bytes of content",
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte(strings.Repeat("a", gitaccess.MaxBlobSize+1)),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "foo/bar.txt", Change: gitaccess.Add}},
			},
			error:   true,
			message: "document bigger than",
		},
		{
			name: "no locations",
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("asdf"),
				BlobLocations: []*gitaccess.BlobLocationEntry{},
			},
			error:   true,
			message: "cannot create document with no locations",
		},
		{
			name: "invalid locations, empty path",
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("asdf"),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "", Change: gitaccess.Add}},
			},
			error:   true,
			message: "invalid location: no path",
		},
		{
			name: "invalid locations, multiple locations in embeddings mode",
			mode: epoch.EpochModeEmbeddings,
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("asdf"),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "abc", Change: gitaccess.Add}, {Path: "def", Change: gitaccess.Add}, {Path: "xyz", Change: gitaccess.Delete}},
			},
			error:   true,
			message: "cannot create document with multiple locations in DedupeByContentAndPath mode",
		},
		{
			name: "valid locations, single location in embeddings mode",
			mode: epoch.EpochModeEmbeddings,
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("asdf"),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "abc", Change: gitaccess.Add}},
			},
			error: false,
		},
		{
			// NOTE: this was valid for a while, but is now invalid
			name: "invalid locations, multiple locations in embeddings mode, add/delete with the same path",
			mode: epoch.EpochModeEmbeddings,
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("asdf"),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "abc", Change: gitaccess.Add}, {Path: "abc", Change: gitaccess.Delete}},
			},
			error:   true,
			message: "cannot create document with multiple locations in DedupeByContentAndPath mode",
		},
		{
			name: "invalid locations, two locations with same paths, same change type in embeddings mode",
			mode: epoch.EpochModeEmbeddings,
			blob: &gitaccess.BlobContentChange{
				ObjectID:      helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
				Content:       []byte("asdf"),
				BlobLocations: []*gitaccess.BlobLocationEntry{{Path: "abc", Change: gitaccess.Delete}, {Path: "abc", Change: gitaccess.Delete}}, // This shouldn't be possible
			},
			error:   true,
			message: "cannot create document with multiple locations in DedupeByContentAndPath mode",
		},
	}

	for _, test := range tests {
		test := test
		t.Run(test.name, func(t *testing.T) {
			msg.EpochMode = test.mode
			doc, err := NewGitDocumentFromContent(context.Background(), &msg, test.blob)
			if test.error {
				require.Nil(t, doc)
				require.Error(t, err)
				require.Contains(t, err.Error(), test.message)
			} else {
				require.NoError(t, err)
			}
		})

	}
}

func Test_panicWhenNotStarted(t *testing.T) {
	t.Run("NewGitDocumentFromContent", func(t *testing.T) {
		require.Panics(t, func() {
			NewGitDocumentFromContent(context.Background(), &messages.Ingest{}, nil) //nolint:errcheck
		})
	})

	t.Run("NewGitDocumentFromOID", func(t *testing.T) {
		require.Panics(t, func() {
			NewGitDocumentFromOID(context.Background(), &messages.Ingest{}, nil) //nolint:errcheck
		})
	})
}

func Test_NewGitDocumentFromContentWithSomeDeletedPaths(t *testing.T) {
	oid := helpers.RandomOID(t)
	msg := &messages.Ingest{
		RepoID:          123,
		OwnerID:         456,
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}
	blob := &gitaccess.BlobContentChange{
		ObjectID: oid,
		Content:  []byte("hello world"),
		BlobLocations: []*gitaccess.BlobLocationEntry{
			{
				Path:   "src/com/example/Foo.java",
				Change: gitaccess.Add,
			},
			{
				Path:   "src/com/example/Bar.java",
				Change: gitaccess.Add,
			},
			{
				Path:   "src/com/example/Baz.java",
				Change: gitaccess.Delete,
			},
		},
	}

	doc, err := NewGitDocumentFromContent(context.Background(), msg, blob)
	require.NoError(t, err)
	requirePaths(t, doc, []string{"src/com/example/Foo.java", "src/com/example/Bar.java", "src/com/example/Baz.java"})

	docDeletedPaths := []string{}
	for _, loc := range doc.Locations {
		if loc.Change == entities.Location_CHANGE_DELETED {
			docDeletedPaths = append(docDeletedPaths, loc.Path)
		}
	}

	require.Equal(t, []string{"src/com/example/Baz.java"}, docDeletedPaths)
}

func Test_DocumentIncludesNodeID(t *testing.T) {
	const (
		repoID    = 123
		repoScore = 100
	)
	corpus := helpers.Corpus(t)
	msg := &messages.Ingest{
		RepoID:    repoID,
		OwnerID:   helpers.OwnerID(t),
		IsPublic:  true,
		RepoScore: repoScore,
		Corpus:    corpus,
		EpochID:   1,
		Topic:     corpus.EpochBackfillTopic(123),
		Partition: helpers.KafkaPartition(t, repoID),
		Offset:    helpers.KafkaOffset(t),
		NetworkID: repoID,
		Head: &gitaccess.RefTip{
			RefName:   "refs/heads/main",
			CommitOID: helpers.UniqueOID(t),
		},
		// Must have at least a single partition
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}
	blob := &gitaccess.BlobContentChange{
		ObjectID: helpers.UniqueOID(t),
		BlobLocations: []*gitaccess.BlobLocationEntry{
			{
				Path:   "foo.txt",
				Change: gitaccess.Add,
			},
			{
				Path:   "bar.txt",
				Change: gitaccess.Add,
			},
		},
		Content: []byte("hello, world"),
	}

	doc, err := NewGitDocumentFromContent(ctx(), msg, blob)
	require.NoError(t, err)

	require.Len(t, doc.Locations, 2)
	require.Equal(t, msg.EntryID, doc.Locations[0].EntryId)
	require.Equal(t, msg.EntryID, doc.Locations[1].EntryId)
}

func Test_NewGitDocumentFromContentDeletedDocument(t *testing.T) {
	oid := helpers.RandomOID(t)
	msg := &messages.Ingest{
		RepoID:          123,
		OwnerID:         456,
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}

	var tests = []struct {
		name        string
		content     string
		inputPaths  []string
		outputPaths []string
		unindexable bool
	}{
		{
			name:        "happy path",
			content:     "nonempty",
			inputPaths:  []string{"path.txt"},
			outputPaths: []string{"path.txt"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			locations := []*gitaccess.BlobLocationEntry{}
			for _, path := range test.inputPaths {
				locations = append(locations, &gitaccess.BlobLocationEntry{Path: path, Change: gitaccess.Delete})
			}

			blob := &gitaccess.BlobContentChange{
				ObjectID:      oid,
				Content:       []byte(test.content),
				BlobLocations: locations,
			}

			doc, err := NewGitDocumentFromContent(context.Background(), msg, blob)
			require.NoError(t, err)

			if test.unindexable {
				require.Error(t, err)
				require.True(t, IsUnindexable(err))
			} else {
				require.NoError(t, err)
				require.True(t, doc.AllLocationsDeleted)
				require.Equal(t, []byte(test.content), doc.Content, "deletes should have content")

				paths := []string{}
				for _, loc := range doc.Locations {
					paths = append(paths, loc.Path)
				}

				require.ElementsMatch(t, test.outputPaths, paths)
			}
		})
	}
}

func Test_NewGitDocumentFromOID(t *testing.T) {
	oid := helpers.RandomOID(t)
	msg := &messages.Ingest{
		RepoID:          123,
		OwnerID:         456,
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}

	var tests = []struct {
		name        string
		inputPaths  []string
		outputPaths []string
		unindexable bool
	}{
		{
			name:        "happy path",
			inputPaths:  []string{"path.txt"},
			outputPaths: []string{"path.txt"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			locations := []*gitaccess.BlobLocationEntry{}
			for _, path := range test.inputPaths {
				locations = append(locations, &gitaccess.BlobLocationEntry{Path: path, Change: gitaccess.Delete})
			}

			blob := &gitaccess.BlobOIDChange{
				ObjectID:      oid,
				BlobLocations: locations,
			}

			doc, err := NewGitDocumentFromOID(context.Background(), msg, blob)
			require.NoError(t, err)

			if test.unindexable {
				require.Error(t, err)
				require.True(t, IsUnindexable(err))
			} else {
				require.NoError(t, err)

				paths := []string{}
				for _, loc := range doc.Locations {
					paths = append(paths, loc.Path)
				}

				require.ElementsMatch(t, test.outputPaths, paths)
			}
		})
	}
}

func Test_NewGitDocumentFromOIDAllLocationsDeleted(t *testing.T) {
	msg := &messages.Ingest{
		RepoID:          123,
		OwnerID:         456,
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}
	blob := &gitaccess.BlobOIDChange{
		ObjectID: helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
		BlobLocations: []*gitaccess.BlobLocationEntry{
			{
				Path:   "foo/deleted.txt",
				Change: gitaccess.Delete,
			},
		},
	}

	doc, err := NewGitDocumentFromOID(context.Background(), msg, blob)
	require.NoError(t, err)
	require.NoError(t, err)
	require.True(t, doc.AllLocationsDeleted)
	require.Len(t, doc.Locations, 1)
	require.Equal(t, "foo/deleted.txt", doc.Locations[0].Path)
}

func Test_NewGitDocumentFromOIDWithEmptyBlobOID(t *testing.T) {
	msg := &messages.Ingest{
		RepoID:          123,
		OwnerID:         456,
		DocumentTopic:   routing.DocumentTopic{Partitions: 1},
		Lease:           messages.NewLease(),
		IngestStartedAt: time.Now(),
	}
	blob := &gitaccess.BlobOIDChange{
		ObjectID: helpers.OID(t, "e69de29bb2d1d6434b8b29ae775ad8c2e48c5391"),
		BlobLocations: []*gitaccess.BlobLocationEntry{
			{
				Path:   "foo.txt",
				Change: gitaccess.Add,
			},
		},
	}
	doc, err := NewGitDocumentFromOID(context.Background(), msg, blob)
	require.Error(t, err)
	require.True(t, IsUnindexable(err))
	require.Nil(t, doc)
}

func requirePaths(t *testing.T, doc *blackbird.GitDocument, expectedPaths []string) {
	t.Helper()

	paths := []string{}
	for _, loc := range doc.Locations {
		paths = append(paths, loc.GetPath())
	}

	require.ElementsMatch(t, expectedPaths, paths)
}

func ctx() context.Context {
	return context.Background()
}

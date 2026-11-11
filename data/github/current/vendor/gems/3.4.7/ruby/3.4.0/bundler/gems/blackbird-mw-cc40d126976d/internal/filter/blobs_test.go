package filter

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_BlobFiltering(t *testing.T) {
	type test struct {
		name         string
		filterBlobs  bool
		expectedDocs int
		docs         [][]*searchpb.GitDocumentMatch
		unresolved   gitaccess.RepoBlobsMap
	}
	tests := []test{
		{
			name:         "asynchronous filtering",
			filterBlobs:  false,
			expectedDocs: 2,
			docs: [][]*searchpb.GitDocumentMatch{{
				fakeDocument(t, "document-1", "path/to/doc-1", helpers.OID(t, "66fdf41bd6393853943ded470d5e664898dede62")),
				fakeDocument(t, "document-2", "path/to/doc-2", helpers.OID(t, "db2b6899b3014dbdd98197ed14ba67433534963c")),
			}},
			unresolved: gitaccess.RepoBlobsMap{
				1: gitaccess.BlobSet{helpers.OIDFromContent(t, "document-1"): true},
			},
		},
		{
			name:         "synchronous filtering",
			filterBlobs:  true,
			expectedDocs: 1,
			docs: [][]*searchpb.GitDocumentMatch{{
				fakeDocument(t, "document-1", "path/to/doc-1", helpers.OID(t, "66fdf41bd6393853943ded470d5e664898dede62")),
				fakeDocument(t, "document-2", "path/to/doc-2", helpers.OID(t, "db2b6899b3014dbdd98197ed14ba67433534963c")),
			}},
			unresolved: gitaccess.RepoBlobsMap{
				1: gitaccess.BlobSet{helpers.OIDFromContent(t, "document-1"): true},
			},
		},
		{
			name:         "synchronous filtering - no unresolved blobs",
			filterBlobs:  true,
			expectedDocs: 2,
			docs: [][]*searchpb.GitDocumentMatch{{
				fakeDocument(t, "document-1", "path/to/doc-1", helpers.OID(t, "66fdf41bd6393853943ded470d5e664898dede62")),
				fakeDocument(t, "document-2", "path/to/doc-2", helpers.OID(t, "db2b6899b3014dbdd98197ed14ba67433534963c")),
			}},
			unresolved: gitaccess.RepoBlobsMap{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			gitClient := &gitaccessfakes.FakeClient{}
			gitClient.ResolveBlobsStub = func(ctx context.Context, rbm gitaccess.RepoBlobsMap) error {
				for r := range rbm {
					rbm[r] = tc.unresolved[r]
				}
				return nil
			}

			f := NewUnresolvableBlobs(gitClient)
			err := f.ApplyL(context.Background(), tc.filterBlobs, 1, tc.docs)

			require.NoError(t, err)
			require.Equal(t, tc.expectedDocs, len(tc.docs[0]))
		})
	}
}

func Test_FilteringZeroLocsPanics(t *testing.T) {
	gitClient := &gitaccessfakes.FakeClient{}
	f := NewUnresolvableBlobs(gitClient)
	require.PanicsWithValue(t, "must set numLocs > 0", func() {
		_ = f.ApplyL(context.Background(), true, 0, [][]*searchpb.GitDocumentMatch{})
	})
}

func fakeDocument(t *testing.T, content string, path string, commitSHA gitaccess.ObjectID) *searchpb.GitDocumentMatch {
	blobSHA := helpers.OIDFromContent(t, content)

	return &searchpb.GitDocumentMatch{
		TermMatches: []*searchpb.Range{},
		Locations: []*searchpb.Location{
			{
				Path:         path,
				RepoId:       1,
				OwnerId:      1,
				CommitSha:    commitSHA.Bytes(),
				IsRepoPublic: false,
				Nwo:          "github/test",
			},
		},
		Content:           []byte(content),
		BlobSha:           blobSHA.Bytes(),
		DocSha:            blobSHA.Bytes(), // NOTE: Assumes hybrid/lexical sharding; does not matter for this test
		LanguageId:        5,
		TotalLocations:    1,
		ScoringInfo:       nil,
		RetrievalPosition: 0,
		MinDocsToRetrieve: 0,
		TermEmbeddings:    nil,
	}
}

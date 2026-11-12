package scoring

import (
	"reflect"
	"testing"

	pb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/test/helpers"
)

func makeDoc(t *testing.T, path string, snippet string, repoID uint32, ownerID uint32, langID uint32, score float32) *pb.GitDocumentMatch {
	blobSHA := helpers.OIDFromContent(t, snippet)

	return &pb.GitDocumentMatch{
		DocSha:  blobSHA.Bytes(), // NOTE: Assumes lexical/hybrid mode sharding; doesn't matter for these tests at this time.
		BlobSha: blobSHA.Bytes(),
		Locations: []*pb.Location{
			{
				Path:    path,
				OwnerId: ownerID,
				RepoId:  repoID,
				Nwo:     "a/b",
			},
		},
		LanguageId: langID,
		Content:    []byte(snippet),
		ScoringInfo: &pb.ScoringInfo{
			Score: score,
			Snippets: []*pb.Snippet{{
				Start: 0,
				End:   uint32(len(snippet)),
			}},
		},
		TermMatches:       nil,
		TotalLocations:    0,
		RetrievalPosition: 0,
		MinDocsToRetrieve: 0,
		TermEmbeddings:    nil,
	}
}

func assertDocs(t *testing.T, expected []string, got []*pb.GitDocumentMatch) {
	t.Helper()
	docs := []string{}
	for _, doc := range got {
		docs = append(docs, doc.Locations[0].Path)
	}

	if !reflect.DeepEqual(expected, docs) {
		t.Log("After crowding:")
		for i := range got {
			t.Logf("%d. [%0.2f] %s (expected %s)\n", i+1, got[i].ScoringInfo.Score, docs[i], expected[i])
		}

		require.FailNow(t, "expected != got")
	}

	require.Equal(t, expected, docs)
}

func TestCrowding(t *testing.T) {
	docs := []*pb.GitDocumentMatch{
		makeDoc(t, "zzz.txt", "", 5, 5, 6, 99.0),
		makeDoc(t, "a/b/c.txt", "", 1, 2, 3, 50.0),
		makeDoc(t, "d/e/c.txt", "", 1, 2, 3, 25.0),
		makeDoc(t, "random.txt", "", 3, 4, 5, 10.0),
		makeDoc(t, "qqq.txt", "", 5, 5, 6, -99.0),
	}
	EnforceCrowding(docs)

	assertDocs(t, []string{
		"zzz.txt",
		"a/b/c.txt",
		"random.txt",
		"d/e/c.txt",
		"qqq.txt",
	}, docs)
}

func TestCrowdingWithSnippets(t *testing.T) {
	snippetA := `
      if supports_path
      	@support_path
      end
      def url_helpers
        @url_helpers ||= Rails.application.routes.url_helpers
      end
	`
	snippetB := `
	end
      end

      def url_helpers
        @url_helpers ||= Rails.application.routes.url_helpers
      end

      # Comment
	`

	docs := []*pb.GitDocumentMatch{
		makeDoc(t, "aaa.txt", snippetA, 1, 2, 3, 99.0),
		makeDoc(t, "bbb.txt", snippetB, 2, 3, 4, 50.0),
		makeDoc(t, "ccc.txt", "", 3, 4, 5, 40.0),
	}

	// Check that snippets similarity is calculated correctly
	ha := getSnippetHash(docs[0])
	hb := getSnippetHash(docs[1])
	hc := getSnippetHash(docs[2])
	require.Equal(t, 1.0, compareSnippetHashes(ha, hb))
	require.Equal(t, 1.0, compareSnippetHashes(hb, ha))
	require.Equal(t, 0.0, compareSnippetHashes(ha, hc))
	require.Equal(t, 0.0, compareSnippetHashes(hb, hc))

	EnforceCrowding(docs)

	assertDocs(t, []string{
		"aaa.txt",
		"ccc.txt",
		// Since snippet A and B are similar, punish bbb.txt
		"bbb.txt",
	}, docs)
}

func TestCrowdingBreakTiesWithDocSha(t *testing.T) {
	docs := []*pb.GitDocumentMatch{
		makeDoc(t, "aaa.txt", "hello world snippet", 1, 2, 3, 99.0),
		makeDoc(t, "aaa.txt", "hello world snippet", 1, 2, 3, 99.0),
		makeDoc(t, "aaa.txt", "hello world snippet", 1, 2, 3, 99.0),
		makeDoc(t, "aaa.txt", "hello world snippet", 1, 2, 3, 99.0),
		makeDoc(t, "aaa.txt", "hello world snippet", 1, 2, 3, 99.0),
	}

	for i, doc := range docs {
		doc.DocSha = []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, uint8(i)}
	}

	EnforceCrowding(docs)

	// first document is not reordered by crowding; subsequent ties are ordered by doc sha descending
	require.Equal(t, []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0}, docs[0].DocSha, "first doc should not be reordered")

	for i, doc := range docs[1:] {
		require.Equal(t, []byte{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, uint8(len(docs) - (i + 1))}, doc.DocSha, "document %d is not in the expected location", i+1)
	}
}

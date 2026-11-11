package blackbird

import (
	"math/rand"
	"testing"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/stretchr/testify/require"
)

func TestEstimatedCounts(t *testing.T) {
	docs := []*searchpb.GitDocumentMatch{}

	s1 := rand.NewSource(0)
	r1 := rand.New(s1)

	for i := 0; i < 1024; i++ {
		data := make([]byte, 20)
		r1.Read(data)
		// NOTE: Only Doc SHA matters for this test
		//nolint:exhaustruct
		docs = append(docs, &searchpb.GitDocumentMatch{
			DocSha: data,
		})
	}

	est := getFirstNonSaturatedBucket(&searchpb.SearchResponse{Documents: docs})

	require.Equal(t, 2048, len(est.docs)*est.multiplier)
}

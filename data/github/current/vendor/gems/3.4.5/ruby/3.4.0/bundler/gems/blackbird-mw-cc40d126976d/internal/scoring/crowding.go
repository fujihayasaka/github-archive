package scoring

import (
	"bytes"
	"hash/fnv"
	"math"
	"sort"
	"strings"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
)

const (
	// SimilarityPenalty is the scoring penalty if two files are identical.
	SimilarityPenalty = 50.0

	// CrowdingDepth is the number of results to enforce crowding on (20
	// results = 1st page of results)
	CrowdingDepth = 20
)

func getFilename(path string) string {
	segments := strings.Split(path, "/")
	return segments[len(segments)-1]
}

// Similarity is a score from 0 (dissimilar) to 1 (identical).
func similarity(a, b *searchpb.GitDocumentMatch, ha, hb map[uint64]struct{}) float64 {
	sameRepo := 0.0
	sameOrg := 0.0
	sameFilename := 0.0
	if len(a.Locations) > 0 && len(b.Locations) > 0 {
		if a.Locations[0].RepoId == b.Locations[0].RepoId {
			sameRepo = 1.0
		}
		if a.Locations[0].OwnerId == b.Locations[0].OwnerId {
			sameOrg = 1.0
		}
		if getFilename(a.Locations[0].Path) == getFilename(b.Locations[0].Path) {
			sameFilename = 1.0
		}
	}

	sameLanguage := 0.0
	if a.LanguageId == b.LanguageId {
		sameLanguage = 1.0
	}

	return (0.50*compareSnippetHashes(ha, hb) +
		0.25*sameRepo +
		0.15*sameFilename +
		0.10*sameOrg +
		0.01*sameLanguage)
}

func getSnippetHash(doc *searchpb.GitDocumentMatch) map[uint64]struct{} {
	out := map[uint64]struct{}{}
	for _, snippet := range doc.ScoringInfo.Snippets {
		snippetContent := ""
		if snippet.Start < snippet.End && int(snippet.Start) <= len(doc.Content) && int(snippet.End) <= len(doc.Content) {
			snippetContent = string(doc.Content[snippet.Start:snippet.End])
		}

		for _, line := range strings.Split(snippetContent, "\n") {
			// Only consider "substantive" lines from the snippet
			if len(strings.TrimSpace(line)) > 10 {
				hash := fnv.New64a()
				hash.Write([]byte(line))
				out[hash.Sum64()] = struct{}{}
			}
		}
	}
	return out
}

func compareSnippetHashes(a, b map[uint64]struct{}) float64 {
	same := 0
	for k := range a {
		if _, ok := b[k]; ok {
			same++
		}
	}

	return math.Min(float64(same), 3.0) / math.Max(1.0, math.Min(float64(len(a)), float64(len(b))))
}

func EnforceCrowding(docs []*searchpb.GitDocumentMatch) {
	// Precalculate snippet similarity
	snippetHashes := []map[uint64]struct{}{}
	for _, doc := range docs {
		snippetHashes = append(snippetHashes, getSnippetHash(doc))
	}

	// TODO: maybe further limit the number of documents that participate in crowding?
	for i := 0; i < len(docs)-1; i++ {
		if i >= CrowdingDepth {
			break
		}

		for j := i + 1; j < len(docs); j++ {
			s := similarity(docs[i], docs[j], snippetHashes[i], snippetHashes[j])
			penalty := float32(-1.0 * SimilarityPenalty * s)
			if penalty != 0 {
				docs[j].ScoringInfo.Score += penalty

				// Record the penalty in the crowding factor
				if len(docs[j].ScoringInfo.Factors) == 0 || docs[j].ScoringInfo.Factors[len(docs[j].ScoringInfo.Factors)-1].Kind != searchpb.ScoringFactorKind_SCORING_FACTOR_KIND_CROWDING {
					docs[j].ScoringInfo.Factors = append(docs[j].ScoringInfo.Factors, &searchpb.ScoringContribution{
						Kind:         searchpb.ScoringFactorKind_SCORING_FACTOR_KIND_CROWDING,
						Contribution: penalty,
					})
				} else {
					docs[j].ScoringInfo.Factors[len(docs[j].ScoringInfo.Factors)-1].Contribution += penalty
				}
			}
		}

		// Sort the remaining docs by the new scores, break ties by Doc SHA
		start := i + 1
		sort.Slice(docs[start:], func(i, j int) bool {
			if docs[start+i].ScoringInfo.Score != docs[start+j].ScoringInfo.Score {
				return docs[start+i].ScoringInfo.Score > docs[start+j].ScoringInfo.Score
			}
			return bytes.Compare(docs[start+i].DocSha, docs[start+j].DocSha) > 0
		})
	}
}

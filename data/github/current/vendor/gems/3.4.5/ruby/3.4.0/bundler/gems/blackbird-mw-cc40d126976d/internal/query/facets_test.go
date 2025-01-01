package query

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/constants"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/types"
)

func TestFacetGeneration(t *testing.T) {
	for _, tenant := range []*pb.Tenant{nil, {Shortcode: "bigco"}} {
		blackbirdRepo := types.NWOFromString("github/blackbird")
		f := NewFacetsExtractor()
		f.AddDocument(makeFacetDoc(t, blackbirdRepo.NameWithUniqueOwner(tenant), "a/b/c.rs", 15.0))

		// There should be no facets if only one document exists
		out := f.GetFacets(tenant)
		require.Equal(t, 0, len(out))

		// Adding a document with a new repo should create a repo facet only
		githubRepo := types.NWOFromString("github/github")
		f.AddDocument(makeFacetDoc(t, githubRepo.NameWithUniqueOwner(tenant), "a/b/c.rs", 12.0))

		expected := []*pb.Facet{{
			Kind: pb.FacetKind_FACET_KIND_REPO,
			Entries: []*pb.FacetEntry{
				// github/blackbird should come first, since it's alphabetically first
				{
					Name:  "github/blackbird",
					Owner: "github",
					Query: "repo:github/blackbird",
				},
				{
					Name:  "github/github",
					Owner: "github",
					Query: "repo:github/github",
				},
			},
		}}
		out = f.GetFacets(tenant)
		require.Equal(t, 1, len(out))
		require.Equal(t, expected, out)

		// Adding a document with a new path should create a path facet
		f.AddDocument(makeFacetDoc(t, blackbirdRepo.NameWithUniqueOwner(tenant), "src/app/tooling.rs", 12.0))

		// Regex meta characters should be escaped.
		f.AddDocument(makeFacetDoc(t, blackbirdRepo.NameWithUniqueOwner(tenant), ".github/workflows/release.yaml", 10.0))
		f.AddDocument(makeFacetDoc(t, blackbirdRepo.NameWithUniqueOwner(tenant), `\.+*?()|[]{}^$/file.yaml`, 10.0))

		expected = []*pb.Facet{
			{
				Kind: pb.FacetKind_FACET_KIND_LANGUAGE,
				Entries: []*pb.FacetEntry{
					{
						Name:          "Rust", // Rust should come first, since it's scored higher
						LanguageColor: "#dea584",
						Query:         "language:Rust",
					},
					{
						Name:          "YAML",
						LanguageColor: "#cb171e", // Modern linguist does not have a color for protobuf
						Query:         "language:YAML",
					},
				},
			},
			{
				Kind: pb.FacetKind_FACET_KIND_REPO,
				Entries: []*pb.FacetEntry{
					// github/blackbird should now come first, since it is alphabetically first
					{
						Name:  "github/blackbird",
						Owner: "github",
						Query: "repo:github/blackbird",
					},
					{
						Name:  "github/github",
						Owner: "github",
						Query: "repo:github/github",
					},
				},
			},
			{
				Kind: pb.FacetKind_FACET_KIND_PATH,
				Entries: []*pb.FacetEntry{
					{
						Name:  ".github/workflows/",
						Query: `path:/^\.github\/workflows\//`,
					},
					{
						Name:  `\.+*?()|[]{}^$/`,
						Query: `path:/^\\\.\+\*\?\(\)\|\[\]\{\}\^\$\//`,
					},
					{
						Name:  "a/b/",
						Query: `path:/^a\/b\//`,
					},
					{
						Name:  "src/app/",
						Query: `path:/^src\/app\//`,
					},
				},
			},
		}
		out = f.GetFacets(tenant)
		require.Equal(t, 3, len(out), "unexpected facets: %+v", out)
		require.Equal(t, expected, out)
	}
}

func TestLanguageFacets(t *testing.T) {
	f := NewFacetsExtractor()
	f.AddDocument(makeFacetDoc(t, "github/blackbird", "a/b/c.rs", 12.0))
	f.AddDocument(makeFacetDoc(t, "github/blackbird", "service.proto", 10.0))

	expected := []*pb.Facet{{
		Kind: pb.FacetKind_FACET_KIND_LANGUAGE,
		Entries: []*pb.FacetEntry{
			// Rust should come first, since it's scored higher
			{
				Name:          "Rust",
				LanguageColor: "#dea584",
				Query:         "language:Rust",
			},
			// Protobuf's query should be escaped since the full name is "Protocol Buffer"
			{
				Name:          "Protocol Buffer",
				LanguageColor: "", // Modern linguist does not have a color for protobuf
				Query:         "language:\"Protocol Buffer\"",
			},
		},
	}}
	out := f.GetFacets(nil /* tenant */)
	require.Equal(t, 1, len(out))
	require.Equal(t, expected, out)
}

func TestManyFacets(t *testing.T) {
	f := NewFacetsExtractor()
	f.AddDocument(makeFacetDoc(t, "github/best", "service.proto", 10.0))
	f.AddDocument(makeFacetDoc(t, "github/second", "service.proto", 9.0))
	f.AddDocument(makeFacetDoc(t, "github/third", "service.proto", 8.0))
	f.AddDocument(makeFacetDoc(t, "github/fourth", "service.proto", 7.0))
	f.AddDocument(makeFacetDoc(t, "github/fifth", "service.proto", 6.0))
	f.AddDocument(makeFacetDoc(t, "github/sixth", "service.proto", 5.0))
	f.AddDocument(makeFacetDoc(t, "github/seventh", "service.proto", 4.0))
	f.AddDocument(makeFacetDoc(t, "github/eighth", "service.proto", 3.0))
	f.AddDocument(makeFacetDoc(t, "github/ninth", "service.proto", 2.0))

	expected := []*pb.Facet{{
		Kind: pb.FacetKind_FACET_KIND_REPO,
		Entries: []*pb.FacetEntry{
			// The repositories should be in alphabetical order, not scored order. But note
			// that the ninth repo didn't get a facet, since it was scored too low.
			{
				Name:  "github/best",
				Owner: "github",
				Query: "repo:github/best",
			},
			{
				Name:  "github/fifth",
				Owner: "github",
				Query: "repo:github/fifth",
			},
			{
				Name:  "github/fourth",
				Owner: "github",
				Query: "repo:github/fourth",
			},
			{
				Name:  "github/second",
				Owner: "github",
				Query: "repo:github/second",
			},
			{
				Name:  "github/third",
				Owner: "github",
				Query: "repo:github/third",
			},
		},
	}}
	out := f.GetFacets(nil /* tenant */)
	require.Equal(t, 1, len(out))
	require.Equal(t, expected, out)
}

// makeFacetDoc is a helper for making a GitDocumentMatch for facets.
func makeFacetDoc(t *testing.T, nwo string, path string, score float32) *pb.GitDocumentMatch {
	//nolint:exhaustruct
	return &pb.GitDocumentMatch{
		TermMatches: []*pb.Range{},
		Locations: []*pb.Location{{
			Path:    path,
			RepoNwo: nwo,
		}},
		LanguageId:  languageIDForPath(t, path),
		ScoringInfo: &pb.ScoringInfo{Score: score},
	}
}

const (
	rustLang  uint32 = 327
	yamlLang  uint32 = 407
	protoLang uint32 = 297
)

var languages = map[string]uint32{
	".rs":    rustLang,
	".yaml":  yamlLang,
	".proto": protoLang,
}

func languageIDForPath(t *testing.T, path string) uint32 {
	id, ok := languages[filepath.Ext(path)]
	if !ok {
		return constants.UnknownLanguageId
	}
	return id
}

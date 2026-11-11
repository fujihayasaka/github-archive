package query

import (
	"fmt"
	"math"
	"regexp"
	"sort"
	"strings"

	"github.com/github/blackbird/crates/linguist/pkg/linguist"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/types"
)

const FACET_LIMIT = 5

type FacetRecord struct {
	name        string
	id          uint32
	occurrences int
	score       float64
}

type FacetsExtractor struct {
	languages map[string]*FacetRecord
	repos     map[string]*FacetRecord
	paths     map[string]*FacetRecord
}

func NewFacetsExtractor() FacetsExtractor {
	return FacetsExtractor{
		languages: map[string]*FacetRecord{},
		repos:     map[string]*FacetRecord{},
		paths:     map[string]*FacetRecord{},
	}
}

func (f *FacetsExtractor) AddDocument(doc *pb.GitDocumentMatch) {
	// Set up language facets
	lang, err := linguist.GetLanguageName(doc.LanguageId)
	if err != nil {
		// Don't produce facets for unrecognized languages
		return
	}

	if _, ok := f.languages[lang]; !ok {
		f.languages[lang] = &FacetRecord{
			name: lang,
			id:   doc.LanguageId,
		}
	}
	f.languages[lang].occurrences++
	// NOTE: Use exp(score) because negative scores should still contribute positively
	f.languages[lang].score += math.Exp(float64(doc.ScoringInfo.Score))

	// Set up repository facets
	repo := doc.Locations[0].RepoNwo
	if _, ok := f.repos[repo]; !ok {
		f.repos[repo] = &FacetRecord{
			name: repo,
		}
	}
	f.repos[repo].occurrences++
	// NOTE: Use exp(score) because negative scores should still contribute positively
	f.repos[repo].score += math.Exp(float64(doc.ScoringInfo.Score))

	// Set up path facets
	for _, location := range doc.Locations {
		path := ""
		segments := strings.Split(location.Path, "/")
		specificityBoost := 0.0
		for _, segment := range segments[:len(segments)-1] {
			path += segment + "/"
			if _, ok := f.paths[path]; !ok {
				f.paths[path] = &FacetRecord{
					name:  path,
					score: specificityBoost,
				}
			}

			f.paths[path].occurrences++
			f.paths[path].score += 1.0
			specificityBoost += 0.25
		}
	}
}

func topFacets(stats map[string]*FacetRecord) []FacetRecord {
	output := []FacetRecord{}
	for _, v := range stats {
		output = append(output, *v)
	}

	sort.Slice(output, func(i, j int) bool {
		return output[i].score > output[j].score
	})
	end := len(output)
	if end > FACET_LIMIT {
		end = FACET_LIMIT
	}
	return output[:end]
}

func (f *FacetsExtractor) GetFacets(tenant *pb.Tenant) []*pb.Facet {
	output := []*pb.Facet{}

	languageFacets := &pb.Facet{
		Kind: pb.FacetKind_FACET_KIND_LANGUAGE,
	}
	for _, facet := range topFacets(f.languages) {
		out := &pb.FacetEntry{}
		out.Name = facet.name
		if color, err := linguist.GetLanguageColor(facet.id); err == nil {
			out.LanguageColor = color
		}

		if strings.Contains(facet.name, " ") {
			out.Query = fmt.Sprintf("language:%q", facet.name)
		} else {
			out.Query = fmt.Sprintf("language:%s", facet.name)
		}

		languageFacets.Entries = append(languageFacets.Entries, out)
	}
	if len(languageFacets.Entries) > 1 {
		output = append(output, languageFacets)
	}

	repoFacets := &pb.Facet{
		Kind: pb.FacetKind_FACET_KIND_REPO,
	}
	for _, facet := range topFacets(f.repos) {
		// NB: Facets must produce display nwos and logins
		nwo, err := types.NewNWO(facet.name)
		if err != nil {
			continue
		}
		repo := nwo.NameWithDisplayOwner(tenant)
		repoFacets.Entries = append(repoFacets.Entries, &pb.FacetEntry{
			Owner: nwo.Owner().DisplayLogin(tenant),
			Name:  repo,
			Query: fmt.Sprintf("repo:%s", repo),
		})
	}

	// After choosing the top facets by relevance, sort the path facets by
	// name, so that they are hierarchically organized
	sort.Slice(repoFacets.Entries, func(i, j int) bool {
		return repoFacets.Entries[i].Name < repoFacets.Entries[j].Name
	})

	if len(repoFacets.Entries) > 1 {
		output = append(output, repoFacets)
	}

	pathFacets := &pb.Facet{
		Kind: pb.FacetKind_FACET_KIND_PATH,
	}

	// Suppress lower scoring and more general path facets
	for path, entry := range f.paths {
		parent := ""
		for _, segment := range strings.Split(path, "/") {
			parent += segment + "/"
			if parentScore, ok := f.paths[parent]; ok && entry.score > parentScore.score {
				delete(f.paths, parent)
			}
		}
	}
	for _, facet := range topFacets(f.paths) {
		out := &pb.FacetEntry{}
		out.Name = facet.name
		out.Query = fmt.Sprintf("path:/^%s/", strings.ReplaceAll(regexp.QuoteMeta(facet.name), "/", `\/`))
		pathFacets.Entries = append(pathFacets.Entries, out)
	}

	// After choosing the top facets by relevance, sort the path facets by
	// name, so that they are hierarchically organized
	sort.Slice(pathFacets.Entries, func(i, j int) bool {
		return pathFacets.Entries[i].Name < pathFacets.Entries[j].Name
	})

	if len(pathFacets.Entries) > 1 {
		output = append(output, pathFacets)
	}

	return output
}

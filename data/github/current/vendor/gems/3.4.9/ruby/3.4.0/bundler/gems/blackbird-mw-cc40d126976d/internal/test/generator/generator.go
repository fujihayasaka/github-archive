package generator

import (
	"fmt"
	"math"
	"math/rand"
	"sort"
	"testing"
	"time"

	"github.com/github/blackbird/crates/client/pkg/blackbird"
	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func SearchClustersWithDocuments(t *testing.T, numHosts int, cost float32, servingCorpus routing.Corpus) (*routing.SearchClusters, []*searchpb.GitDocumentMatch) {
	t.Helper()

	bbDocs := []*searchpb.GitDocumentMatch{}
	clients := map[routing.Corpus]blackbird.Client{}
	for _, corpus := range routing.Corpora {
		hosts := make([][]*blackbird.IndexHost, numHosts)
		for i := 0; i < numHosts; i++ {
			bbResp := BlackbirdResponse(t, i, 3, 3)
			bbResp.Stats.Cost = cost / float32(numHosts)
			bbDocs = append(bbDocs, bbResp.Documents...)
			mockClient := &mocks.FakeSearchAPI{}
			mockClient.SearchReturns(bbResp, nil)

			hostname := fmt.Sprintf("shard-%s-%d", corpus.String(), i)
			hosts[i] = []*blackbird.IndexHost{{Hostname: hostname, SearchClient: mockClient}}
		}

		client := &mocks.FakeBlackbirdClient{}
		client.RoutesReturns(blackbird.Routes{Hosts: hosts, ServingOffset: 10, ServingTs: time.Now().UTC().UnixMilli(), Epoch: 1})
		if corpus == servingCorpus {
			client.IsServingReturns(true)
		}
		clients[corpus] = client
	}

	return routing.NewSearchClusters(clients), bbDocs
}

type RepoSpec struct {
	RepoID          types.RepoID
	OwnerID         uint32
	Public          bool
	NumLocsPerDoc   int
	DocsToReturn    int
	DocsWithContent int
	ShardID         int
}

const TestActorID = 1

func QueryServiceRequest(t *testing.T, query string, docLimit uint32, locLimit uint32) *pb.QueryRequest {
	t.Helper()
	return &pb.QueryRequest{
		Query:                 query,
		DocumentLimit:         docLimit,
		QueryParser:           0,
		DocumentLocationLimit: locLimit,
		Actor: &pb.Actor{
			ActorId:     TestActorID, // Must match what's in the auth cache
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
}

func QueryServiceRequestWithExperiments(t *testing.T, query string, docLimit uint32, locLimit uint32, exps map[string]string) *pb.QueryRequest {
	t.Helper()
	return &pb.QueryRequest{
		Query:                 query,
		DocumentLimit:         docLimit,
		QueryParser:           0,
		DocumentLocationLimit: locLimit,
		Actor: &pb.Actor{
			ActorId:     TestActorID, // Must match what's in the auth cache
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
		Experiments: exps,
	}
}

func SuggestServiceRequest(t *testing.T, query string, docLimit uint32, locLimit uint32) *pb.SuggestRequest {
	t.Helper()
	return &pb.SuggestRequest{
		Query: query,
		Actor: &pb.Actor{
			ActorId:     TestActorID, // Must match what's in the auth cache
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
}

func FrontendQueryServiceRequest(t *testing.T, query string, docLimit uint32, locLimit uint32) *pb.FrontendQueryRequest {
	t.Helper()
	return &pb.FrontendQueryRequest{
		Query:                 query,
		DocumentLimit:         docLimit,
		DocumentLocationLimit: locLimit,
		Actor: &pb.Actor{
			ActorId:     TestActorID, // Must match what's in the auth cache
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
}

func CountServiceRequest(t *testing.T, query string) *pb.CountRequest {
	t.Helper()
	return &pb.CountRequest{
		Query: query,
		Actor: &pb.Actor{
			ActorId:     TestActorID, // Must match what's in the auth cache
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
}

func LegacyQueryServiceRequest(t *testing.T, query string, docLimit uint32, locLimit uint32) *pb.LegacyQueryRequest {
	t.Helper()
	return &pb.LegacyQueryRequest{
		Query:                 query,
		DocumentLimit:         docLimit,
		DocumentLocationLimit: locLimit,
		Actor: &pb.Actor{
			ActorId:     TestActorID, // Must match what's in the auth cache
			RequestIp:   "127.0.0.1",
			AccessToken: "asdf",
		},
	}
}

func BlackbirdResponseFromSpec(t *testing.T, specs ...RepoSpec) *searchpb.SearchResponse {
	t.Helper()
	docs := documents(t, specs...)
	return &searchpb.SearchResponse{
		Documents:     docs,
		Stats:         Stats(t, docs),
		ServingStatus: Status(t),
	}
}

func Status(t *testing.T) *servingpb.ServingStatus {
	return &servingpb.ServingStatus{IndexVersion: 1, Shards: []*servingpb.Shard{{ServingTs: time.Now().UnixMilli()}}}
}

func Stats(t *testing.T, docs []*searchpb.GitDocumentMatch) *searchpb.QueryStats {
	t.Helper()
	numDocs := uint32(len(docs))
	return &searchpb.QueryStats{
		DocsRetrieved:         numDocs,
		DocsScored:            numDocs,
		HitRetrievalLimit:     false,
		ScoringDurationMicros: rand.Uint32(),
		HadPanic:              false,
		HadTimeout:            false,
	}
}

func BlackbirdResponse(t *testing.T, shardID int, docsToReturn int, docsWithContent int) *searchpb.SearchResponse {
	t.Helper()
	spec := RepoSpec{
		RepoID:          types.RepoID(rand.Uint32()),
		OwnerID:         rand.Uint32(),
		DocsToReturn:    docsToReturn,
		DocsWithContent: docsWithContent,
		NumLocsPerDoc:   1 + rand.Intn(3),
		Public:          true,
		ShardID:         shardID,
	}

	return BlackbirdResponseFromSpec(t, spec)
}

func BlackbirdResponseWithRepoID(t *testing.T, shardID int, docsToReturn, docsWithContent int, repoID types.RepoID) *searchpb.SearchResponse {
	t.Helper()
	spec := RepoSpec{
		RepoID:          repoID,
		OwnerID:         rand.Uint32(),
		DocsToReturn:    docsToReturn,
		DocsWithContent: docsWithContent,
		NumLocsPerDoc:   1 + rand.Intn(3),
		Public:          true,
		ShardID:         shardID,
	}

	return BlackbirdResponseFromSpec(t, spec)
}

func ScoringInfo(t *testing.T) *searchpb.ScoringInfo {
	t.Helper()
	score := helpers.Score(t)
	return &searchpb.ScoringInfo{
		Score: score,
		Factors: []*searchpb.ScoringContribution{
			{
				Kind:         searchpb.ScoringFactorKind(1 + rand.Intn(11)),
				Contribution: score,
			},
		},
		Snippets: []*searchpb.Snippet{},
	}
}

func documents(t *testing.T, specs ...RepoSpec) []*searchpb.GitDocumentMatch {
	docs := []*searchpb.GitDocumentMatch{}

	for _, repoSpec := range specs {
		for i := 0; i < repoSpec.DocsToReturn; i++ {
			withContent := i < repoSpec.DocsWithContent
			docs = append(docs, document(t, i, repoSpec, withContent))
		}
	}

	sort.Slice(docs, func(i, j int) bool {
		return docs[i].ScoringInfo.Score > docs[j].ScoringInfo.Score
	})
	return docs
}

func document(t *testing.T, pos int, repoSpec RepoSpec, withContent bool) *searchpb.GitDocumentMatch {
	locs := locations(t, repoSpec)
	blobSHA, content := helpers.Content(t, repoSpec.ShardID, pos)

	score := float32(1 / math.Log2(float64(pos+2)))
	scoringInfo := &searchpb.ScoringInfo{
		Score: score,
		Factors: []*searchpb.ScoringContribution{
			{
				Kind:         searchpb.ScoringFactorKind(1 + rand.Intn(11)),
				Contribution: score,
			},
		},
	}

	doc := &searchpb.GitDocumentMatch{
		LanguageId:        1 + rand.Uint32(),
		Locations:         locs,
		TotalLocations:    uint32(len(locs)),
		RetrievalPosition: uint32(pos),
		ScoringInfo:       scoringInfo,
		BlobSha:           blobSHA,
		DocSha:            blobSHA, // TODO: calculate doc sha based on epoch mode
		Content:           nil,
		TermMatches:       nil,
		MinDocsToRetrieve: 0,
		TermEmbeddings:    nil,
	}

	if withContent {
		doc.Content = content
		doc.TermMatches = []*searchpb.Range{{Start: 0, End: 1}}
	}

	return doc
}

func locations(t *testing.T, repoSpec RepoSpec) []*searchpb.Location {
	locations := []*searchpb.Location{}
	for i := 0; i < repoSpec.NumLocsPerDoc; i++ {
		locations = append(locations, location(t, repoSpec))
	}
	return locations
}

func location(t *testing.T, repoSpec RepoSpec) *searchpb.Location {
	return &searchpb.Location{
		Path:         "/path/to/file/test.txt",
		RepoId:       uint32(repoSpec.RepoID),
		Nwo:          "a/b",
		OwnerId:      repoSpec.OwnerID,
		CommitSha:    helpers.UniqueOID(t).Bytes(),
		RefName:      "refs/head/main",
		RepoScore:    rand.Int31(),
		IsRepoPublic: repoSpec.Public,
	}
}

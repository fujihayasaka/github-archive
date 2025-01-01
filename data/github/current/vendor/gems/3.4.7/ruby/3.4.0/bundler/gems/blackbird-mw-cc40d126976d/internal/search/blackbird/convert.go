package blackbird

import (
	"fmt"
	"math"
	"time"

	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/durationpb"

	bb "github.com/github/blackbird/crates/client/pkg/blackbird"
	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/models"
	pb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/query/timing"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/types"
)

//
// Map between blackbird and blackbird-mw's protos (and db models)
//

func toRepo(actor *models.Actor, res *snapshotpb.SearchSnapshotsResponse) (*db.Repository, error) {
	for _, s := range res.Snapshots {
		for _, e := range s.Entries {
			if entryIsAccessibleBy(e, actor) {
				return entryToRepo(e)
			}
		}
	}

	// not found
	return nil, nil
}

func entryToRepo(e *snapshotpb.SnapshotEntry) (*db.Repository, error) {
	repoID := types.RepoID(e.RepoId)

	nwo, err := types.NewNWO(e.Nwo) // NB: OK to use unique nwo for db representation
	if err != nil {
		return nil, fmt.Errorf("invalid NWO %v found in index for entry ID: %v, repo ID: %v; this may indicate corrupt index data. %v", e.Nwo, e.EntryId, e.RepoId, err)
	}

	return &db.Repository{
		RepoID:     repoID,
		OwnerID:    e.OwnerId,
		OwnerLogin: nwo.Owner().String(),
		Name:       nwo.Name(),
		IsPublic:   e.IsRepoPublic,
		IsArchived: e.IsRepoArchived,
		// NB: Can't fill out all fields here
	}, nil
}

func entryToOwner(e *snapshotpb.SnapshotEntry) *models.Owner {
	nwo := types.NWOFromString(e.Nwo) // NB: OK to use unique nwo for db representation
	return &models.Owner{
		OwnerID:    e.OwnerId,
		OwnerLogin: nwo.Owner().String(),
	}
}

func entryIsAccessibleBy(e *snapshotpb.SnapshotEntry, actor *models.Actor) bool {
	if e.IsRepoPublic {
		return true
	}
	return actor != nil && actor.AccessiblePrivateRepoIDs[types.RepoID(e.RepoId)]
}

func mapShardMetadata(resp *routing.ShardResponse) *pb.ShardMetadata {
	var status *servingpb.ServingStatus
	switch {
	case resp.BBResponse != nil:
		status = resp.BBResponse.ServingStatus
	case resp.LastError != nil:
		status, _ = bb.ServingStatus(resp.LastError)
		if status == nil {
			status = &servingpb.ServingStatus{}
		}
	default:
		panic("neither BBResponse nor LastError set")
	}

	// TODO: Eventually this needs to handle that there are multiple shards. Either by recording all of them
	// or by including the shard ID that the response is for.
	minServingOffset := int64(math.MaxInt64)
	for _, indexShard := range status.GetShards() {
		if indexShard.ServingOffset < minServingOffset {
			minServingOffset = indexShard.ServingOffset
		}
	}

	return &pb.ShardMetadata{
		Hostname:       resp.ServingHost,
		ResponseMicros: resp.Duration.Microseconds(),
		Stats:          mapQueryStats(resp.BBResponse),
		Error:          mapShardError(resp.LastError),
		Status: &pb.ShardStatus{
			IndexVersion:  status.GetIndexVersion(),
			Sha:           status.GetSha(),
			ServingOffset: minServingOffset,
			EpochId:       status.GetEpochId(),
			EpochMode:     status.GetEpochMode(),
		},
	}
}

func mapShardError(err error) string {
	shardErr := ""

	if err != nil {
		// TODO: add more rich error information, for starters we're just including the error code
		// and the human readable error information to a string.
		if twerr, ok := err.(twirp.Error); ok {
			statusCode := twirp.ServerHTTPStatusFromErrorCode(twerr.Code())
			shardErr = fmt.Sprintf("%d:%s", statusCode, twerr.Msg())
		} else {
			return err.Error()
		}
	}

	return shardErr
}

func mapDocs(bbDocs []*searchpb.GitDocumentMatch, tenant *pb.Tenant) []*pb.GitDocumentMatch {
	docs := make([]*pb.GitDocumentMatch, 0, len(bbDocs))
	for _, doc := range bbDocs {
		locations := make([]*pb.Location, 0, len(doc.Locations))
		for _, loc := range doc.Locations {
			// MUST use tenant aware nwo here b/c this is converting to a user-displayed representation
			nwo := types.NWOFromString(loc.Nwo).NameWithDisplayOwner(tenant)
			locations = append(locations, &pb.Location{
				Path:         loc.Path,
				RepoId:       loc.RepoId,
				OwnerId:      loc.OwnerId,
				CommitSha:    loc.CommitSha,
				RefName:      loc.RefName,
				RepoScore:    loc.RepoScore,
				IsRepoPublic: loc.IsRepoPublic,
				Score:        loc.Score,
				NetworkId:    loc.NetworkId,
				RepoNwo:      nwo,
			})
		}
		docs = append(docs, &pb.GitDocumentMatch{
			Locations:         locations,
			ScoringInfo:       mapScoringInfo(doc.ScoringInfo),
			TermMatches:       mapTermMatches(doc.TermMatches),
			Content:           doc.Content,
			BlobSha:           doc.BlobSha,
			LanguageId:        doc.LanguageId,
			TotalLocations:    doc.TotalLocations,
			RetrievalPosition: doc.RetrievalPosition,
			DocSha:            doc.DocSha,
		})
	}
	return docs
}

func mapScoringInfo(bbScoringInfo *searchpb.ScoringInfo) *pb.ScoringInfo {
	if bbScoringInfo == nil {
		return nil
	}

	return &pb.ScoringInfo{
		Score:            bbScoringInfo.Score,
		Factors:          mapScoringFactors(bbScoringInfo.Factors),
		Snippets:         mapSnippets(bbScoringInfo.Snippets),
		MatchedSymbols:   mapSymbols(bbScoringInfo.MatchedSymbols),
		EnclosingSymbols: mapSymbols(bbScoringInfo.EnclosingSymbols),
	}
}

func mapSymbols(symbols []*searchpb.Symbol) []*pb.Symbol {
	output := []*pb.Symbol{}
	for _, symbol := range symbols {
		output = append(output, &pb.Symbol{
			FullyQualifiedName: symbol.FullyQualifiedName,
			IdentStart:         symbol.IdentStart,
			IdentEnd:           symbol.IdentEnd,
			ExtentStart:        symbol.ExtentStart,
			ExtentEnd:          symbol.ExtentEnd,
			Kind:               symbol.Kind,
		})
	}
	return output
}

func mapSnippets(bbSnippets []*searchpb.Snippet) []*pb.Snippet {
	snippets := []*pb.Snippet{}
	for _, snip := range bbSnippets {
		snippets = append(snippets, &pb.Snippet{
			Start:              snip.Start,
			End:                snip.End,
			StartingLineNumber: snip.StartingLineNumber,
			EndingLineNumber:   snip.EndingLineNumber,
			Score:              snip.Score,
		})
	}
	return snippets
}

func mapScoringFactors(bbFactors []*searchpb.ScoringContribution) []*pb.ScoringContribution {
	mwFactors := make([]*pb.ScoringContribution, len(bbFactors))

	for i, bbFactor := range bbFactors {
		mwFactors[i] = &pb.ScoringContribution{
			Contribution: bbFactor.Contribution,
			Kind:         pb.ScoringFactorKind(bbFactor.Kind),
		}
	}

	return mwFactors
}

func mapTermMatches(bbTermMatches []*searchpb.Range) []*pb.Range {
	mwTermMatches := make([]*pb.Range, len(bbTermMatches))
	for i, bbMatch := range bbTermMatches {
		mwTermMatches[i] = &pb.Range{
			Start: bbMatch.Start,
			End:   bbMatch.End,
		}
	}
	return mwTermMatches
}

func mapQueryStats(bbResp *searchpb.SearchResponse) *pb.QueryStats {
	stats := bbResp.GetStats()
	if stats == nil {
		return nil
	}

	return &pb.QueryStats{
		Cost:                  stats.Cost,
		DocsRetrieved:         stats.DocsRetrieved,
		DocsScored:            stats.DocsScored,
		LocationsRetrieved:    stats.LocationsRetrieved,
		LocationsScored:       stats.LocationsScored,
		ItersCreated:          stats.ItersCreated,
		ScoringDurationMicros: stats.ScoringDurationMicros,
		HadPanic:              stats.HadPanic,
		HadTimeout:            stats.HadTimeout,
		HitRetrievalLimit:     stats.HitRetrievalLimit,
		HitScoringLimit:       stats.HitScoringLimit,
		HitReturnLimit:        stats.HitReturnLimit,
	}
}

func MapTimings(qt *timing.QueryTimings) *pb.Timing {
	if qt == nil {
		return nil
	}

	var prepare, search, fetch, post, cluster, parse, rewrite, lint time.Duration
	for _, t := range qt.Timings {
		switch t.Key {
		case timing.QueryStepPreparedContext:
			prepare = t.Duration
		case timing.QueryStepClusterSelection:
			cluster = t.Duration
		case timing.QueryStepParseQuery:
			parse = t.Duration
		case timing.QueryStepRewriteQuery:
			rewrite = t.Duration
		case timing.QueryStepLintQuery:
			lint = t.Duration
		case timing.QueryStepRanQuery:
			search = t.Duration
		case timing.QueryStepFetchedMissingContent:
			fetch = t.Duration
		case timing.QueryStepResolvedBlobs:
			post = t.Duration
		}
	}

	return &pb.Timing{
		Overall:            durationpb.New(qt.TotalDuration()),
		PreSearch:          durationpb.New(prepare + cluster + parse + rewrite + lint),
		ContextPreparation: durationpb.New(prepare),
		ClusterSelection:   durationpb.New(cluster),
		QueryParsing:       durationpb.New(parse),
		QueryRewriting:     durationpb.New(rewrite),
		QueryLinting:       durationpb.New(lint),

		Search:              durationpb.New(search),
		FetchMissingContent: durationpb.New(fetch),
		PostSearch:          durationpb.New(post),
	}
}

package filter

import (
	"context"
	"errors"
	"time"

	searchpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/search/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-stats"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"

	"github.com/github/blackbird-mw/internal/background"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/query/timing"
	"github.com/github/blackbird-mw/internal/types"
)

// UnresolvableBlobs checks blackbird document locations against git data in
// spokes and either synchronously filters out documents that aren't correctly
// attributed to a repository or asynchronously reports any mismatches.
type UnresolvableBlobs struct {
	gitClient gitaccess.Client
}

func NewUnresolvableBlobs(gitClient gitaccess.Client) *UnresolvableBlobs {
	return &UnresolvableBlobs{gitClient}
}

// Filter a slice of GitDocumentMatches, removing blobs that do not resolve in spokesd.
func (u *UnresolvableBlobs) Apply(ctx context.Context, filter bool, numLocs uint32, docs *[]*searchpb.GitDocumentMatch) error {
	if len(*docs) == 0 {
		return nil
	}

	resp := [][]*searchpb.GitDocumentMatch{*docs}
	err := u.ApplyL(ctx, filter, numLocs, resp)
	if err != nil {
		return err
	}
	*docs = resp[0]

	return nil
}

// Filter a list of GitDocumentMatch slices, removing blobs that do not resolve in spokesd.
func (u *UnresolvableBlobs) ApplyL(ctx context.Context, filter bool, numLocs uint32, docLists [][]*searchpb.GitDocumentMatch) error {
	if filter {
		return u.filterDocLists(ctx, numLocs, docLists)
	}

	newDocLists := make([][]*searchpb.GitDocumentMatch, len(docLists))
	copy(newDocLists, docLists)
	bgCtx := background.Context(ctx)

	go func() {
		u.filterDocLists(bgCtx, numLocs, newDocLists) //nolint:errcheck
	}()
	return nil
}

// Mutates docLists clamping each document to numLocs and removing any location that does not resolve with spokesd.
func (u *UnresolvableBlobs) filterDocLists(ctx context.Context, numLocs uint32, docLists [][]*searchpb.GitDocumentMatch) error {
	// Is the resolve blobs filter enabled? Probers intentionally don't want blob
	// filtering because they are checking for resolution errors.
	if u.gitClient == nil {
		return nil
	}

	if numLocs == 0 {
		panic("must set numLocs > 0")
	}

	start := time.Now()
	unresolvedBlobs := gitaccess.RepoBlobsMap{}
	for _, docs := range docLists {
		for _, d := range docs {
			// NB: Clamp to N locations per document to save some work in spokesd
			// (we only display one in the UI anyway).
			if len(d.Locations) > int(numLocs) {
				d.Locations = d.Locations[:numLocs]
			}

			for _, l := range d.Locations {
				if _, ok := unresolvedBlobs[types.RepoID(l.RepoId)]; !ok {
					unresolvedBlobs[types.RepoID(l.RepoId)] = gitaccess.BlobSet{}
				}
				unresolvedBlobs[types.RepoID(l.RepoId)][gitaccess.NewObjectIDFromBytes(d.BlobSha)] = true
			}
		}
	}

	err := u.gitClient.ResolveBlobs(ctx, unresolvedBlobs)
	if err != nil {
		reason := "spokes"
		if errors.Is(err, context.Canceled) {
			reason = "context_cancelled"
		} else if errors.Is(err, context.DeadlineExceeded) {
			reason = "deadline_exceeded"
		}
		statting.Counter(ctx, "query_service.resolve_blobs_failure", 1, stats.Tags{"reason": reason})
		return err
	}

	defer func() {
		// NB: Only record timings if we don't have an error
		timing.Record(ctx, timing.QueryStepResolvedBlobs, start)
	}()

	// There's no more work to be done if everything was resolved successfully
	if len(unresolvedBlobs) == 0 {
		return nil
	}

	totalUnresolved := 0
	for i, docs := range docLists {
		filteredDocs := []*searchpb.GitDocumentMatch{}
		for _, doc := range docs {
			filteredLocs := []*searchpb.Location{}
			for _, loc := range doc.Locations {
				repoID := types.RepoID(loc.RepoId)
				blobOID := gitaccess.NewObjectIDFromBytes(doc.BlobSha)
				if set, ok := unresolvedBlobs[repoID]; ok {
					if set[blobOID] {
						logging.Error(ctx, "unresolved blob", kvp.Int("repo_id", int(repoID)), kvp.String("blob_oid", blobOID.String()))
						totalUnresolved++
						continue
					}
				}
				filteredLocs = append(filteredLocs, loc)
			}
			if len(filteredLocs) > 0 {
				doc.Locations = filteredLocs
				filteredDocs = append(filteredDocs, doc)
			}
		}
		docLists[i] = filteredDocs
	}

	statting.Counter(ctx, "query_service.resolve_blobs.unresolved", int64(totalUnresolved))
	return nil
}

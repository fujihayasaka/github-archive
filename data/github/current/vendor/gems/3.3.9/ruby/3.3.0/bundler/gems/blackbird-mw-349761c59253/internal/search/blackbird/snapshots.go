package blackbird

import (
	"context"
	"fmt"
	"strings"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/models"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/types"
)

func (c *Cluster) BuildCacheFromQuery(ctx context.Context, isGloballyScoped bool, actor *models.Actor, inner *querypb.Query) (*search.RepoAndOwnerCache, error) {
	// set divor values on the trait: and nwo: qualifiers
	setDivors(ctx, inner)

	// append permissions filter if this is globally scoped
	var query *querypb.Query
	if isGloballyScoped {
		var permissions *querypb.Query
		if actor != nil {
			if len(actor.AccessiblePrivateRepoIDs) > 10 && 2*len(actor.AccessibleOrganizationIDs) < len(actor.AccessiblePrivateRepoIDs) {
				// If looking at owners dramatically reduces the size of the rewrite it's
				// worth filtering by owners and having to do the post processing work.
				ids := make([]int32, 0, len(actor.AccessibleOrganizationIDs))
				for id := range actor.AccessibleOrganizationIDs {
					ids = append(ids, int32(id))
				}
				// (trait:public_repo OR owner_id:<accessible_owner_ids>)
				permissions = &querypb.Query{
					Kind: querypb.QueryKind_QUERY_KIND_OR,
					Subqueries: []*querypb.Query{
						{
							Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
							Domain:      querypb.Domain_DOMAIN_TRAIT,
							ValueString: "public_repo",
						},
						{
							Kind:     querypb.QueryKind_QUERY_KIND_QUALIFIER,
							Domain:   querypb.Domain_DOMAIN_OWNER_ID,
							ValueInt: ids,
						},
					},
				}
			} else {
				// Otherwise: filter by repos
				ids := make([]int32, 0, len(actor.AccessiblePrivateRepoIDs))
				for id := range actor.AccessiblePrivateRepoIDs {
					ids = append(ids, int32(id))
				}
				// (trait:public_repo OR repo_id:<accessible_repo_ids>)
				permissions = &querypb.Query{
					Kind: querypb.QueryKind_QUERY_KIND_OR,
					Subqueries: []*querypb.Query{
						{
							Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
							Domain:      querypb.Domain_DOMAIN_TRAIT,
							ValueString: "public_repo",
						},
						{
							Kind:     querypb.QueryKind_QUERY_KIND_QUALIFIER,
							Domain:   querypb.Domain_DOMAIN_REPO_ID,
							ValueInt: ids,
						},
					},
				}
			}
		} else {
			// trait:public_repo
			permissions = &querypb.Query{
				Kind:        querypb.QueryKind_QUERY_KIND_QUALIFIER,
				Domain:      querypb.Domain_DOMAIN_TRAIT,
				ValueString: "public_repo",
			}
		}

		// (query AND permissions)
		query = &querypb.Query{
			Kind:       querypb.QueryKind_QUERY_KIND_AND,
			Subqueries: []*querypb.Query{inner, permissions},
		}
	} else {
		query = inner
	}

	res, err := c.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource:       string(search.QuerySourceFE),
		QueryAst:          query,
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(c.ServingOffset()),
		EpochId:           uint32(c.EpochID()),
		SnapshotsToReturn: 100000,
		EntriesLimit:      search.DefaultLocsLimit,
	})
	if err != nil {
		logging.Error(ctx, "failed resolve query with snapshot search", kvp.Err(err))
		return nil, err
	}

	cache := search.NewRepoAndOwnerCache()
	for _, s := range res.Snapshots {
		for _, e := range s.Entries {
			// If there is no NWO, exclude the snapshot. This may be the case for some permanent error snapshots.
			if e.Nwo == "" {
				continue
			}

			// Safe to use `NWOFromString` which panics on invalid NWOs because blackbird stores
			// valid NWOs on non-error snapshots.
			nwo := types.NWOFromString(e.Nwo) // NB: use of unique nwo required for query rewriting cache

			// Existence of org/user logins is public knowledge
			// TODO: Is this true in proxima? ^
			owner := &models.Owner{
				OwnerID:    e.OwnerId,
				OwnerLogin: nwo.Owner().String(),
			}
			cache.OwnersByID[e.OwnerId] = owner
			cache.OwnersByLogin[strings.ToLower(nwo.Owner().String())] = owner

			// Filter out private repos that the user doesn't have access to
			if entryIsAccessibleBy(e, actor) {
				cache.ReposByID[types.RepoID(e.RepoId)] = e
				cache.ReposByName[strings.ToLower(nwo.Name())] = append(cache.ReposByName[nwo.Name()], e)
				cache.ReposByNWO[strings.ToLower(e.Nwo)] = e
			}
		}
	}

	return cache, nil
}

func (c *Cluster) GetOwner(ctx context.Context, login string) (*models.Owner, error) {
	res, err := c.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceFE),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_TRAIT,
			ValueString:     fmt.Sprintf("owner_%s", login),
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		},
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(c.ServingOffset()),
		EpochId:           uint32(c.EpochID()),
		SnapshotsToReturn: 1,
		EntriesLimit:      1,
	})
	if err != nil {
		logging.Error(ctx, "failed to get owner with snapshot search", kvp.Err(err))
		return nil, err
	}

	for _, s := range res.Snapshots {
		for _, e := range s.Entries {
			return entryToOwner(e), nil
		}
	}

	// Not found
	return nil, nil
}

func (c *Cluster) GetOwners(ctx context.Context, ids []int64) ([]*models.Owner, error) {
	queries := []*querypb.Query{}
	for _, id := range ids {
		q := &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_OWNER_ID,
			ValueInt:        []int32{int32(id)},
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		}
		queries = append(queries, q)
	}

	res, err := c.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceFE),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_OR,
			Subqueries:      queries,
			DivorToRetrieve: 1,
			DivorToScore:    1,
		},
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(c.ServingOffset()),
		EpochId:           uint32(c.EpochID()),
		SnapshotsToReturn: uint32(len(ids)),
		EntriesLimit:      1,
	})
	if err != nil {
		logging.Error(ctx, "failed to get owners with snapshot search", kvp.Err(err))
		return nil, err
	}

	owners := []*models.Owner{}
	for _, s := range res.Snapshots {
		for _, e := range s.Entries {
			owners = append(owners, entryToOwner(e))
		}
	}

	return owners, nil
}

func (c *Cluster) GetRepositoryByNWO(ctx context.Context, actor *models.Actor, nwo types.NWO) (*db.Repository, error) {
	res, err := c.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceFE),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_TRAIT,
			ValueString:     fmt.Sprintf("nwo_%s", nwo.String()),
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		},
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(c.ServingOffset()),
		EpochId:           uint32(c.EpochID()),
		SnapshotsToReturn: 1,
		EntriesLimit:      1,
	})
	if err != nil {
		logging.Error(ctx, "failed to get repo by nwo with snapshot search", kvp.Err(err), kvp.Any("nwo", nwo), kvp.Any("actor", actor))
		return nil, err
	}
	return toRepo(actor, res)
}

func (c *Cluster) GetRepositoryByID(ctx context.Context, actor *models.Actor, repoID types.RepoID) (*db.Repository, error) {
	res, err := c.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource: string(search.QuerySourceFE),
		QueryAst: &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_REPO_ID,
			ValueInt:        []int32{repoID.ToInt32()},
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		},
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(c.ServingOffset()),
		EpochId:           uint32(c.EpochID()),
		SnapshotsToReturn: 1,
		EntriesLimit:      1,
	})
	if err != nil {
		logging.Error(ctx, "failed to get repo by id with snapshot search", kvp.Err(err), kvp.Any("repo", repoID), kvp.Any("actor", actor))
		return nil, err
	}
	return toRepo(actor, res)
}

func (c *Cluster) SearchSnapshots(ctx context.Context, req *snapshotpb.SearchSnapshotsRequest) (*snapshotpb.SearchSnapshotsResponse, error) {
	host, err := c.RandomHost()
	if err != nil {
		return nil, err
	}

	logging.Info(ctx, "performing snapshot search on a random host", kvp.String("query", serialize(req.QueryAst)), kvp.String("shard_host", host.Hostname), kvp.Int("shard_id", int(host.ShardID)))
	req.ShardId = uint32(host.ShardID)
	return host.SearchSnapshots(ctx, req)
}

func (c *Cluster) SnapshotsInHashInterval(ctx context.Context, hash uint64, desired int) (*snapshotpb.SnapshotsInHashIntervalResponse, error) {
	host, err := c.RandomHost()
	if err != nil {
		return nil, err
	}

	req := &snapshotpb.SnapshotsInHashIntervalRequest{
		ServingOffset:  int64(c.ServingOffset()),
		EpochId:        uint32(c.EpochID()),
		ShardId:        host.ShardID,
		Hash:           hash,
		DesiredResults: uint32(desired),
	}

	return host.SnapshotsInHashInterval(ctx, req)
}

func setDivors(ctx context.Context, query *querypb.Query) {
	switch query.Kind {
	case querypb.QueryKind_QUERY_KIND_QUALIFIER:
		switch query.Domain {
		case querypb.Domain_DOMAIN_OWNER_ID, querypb.Domain_DOMAIN_REPO_ID:
			query.DivorToRetrieve = search.RetrieveAllDocs
			query.DivorToScore = 1
		case querypb.Domain_DOMAIN_TRAIT:
			if strings.HasPrefix(query.ValueString, "nwo_") || strings.HasPrefix(query.ValueString, "repo_") || strings.HasPrefix(query.ValueString, "owner_") {
				query.DivorToRetrieve = search.RetrieveAllDocs
				query.DivorToScore = 1
			}
		case querypb.Domain_DOMAIN_NWO:
			query.DivorToRetrieve = search.RetrieveAllDocs
			query.DivorToScore = 50
		}
	}

	for _, subquery := range query.Subqueries {
		setDivors(ctx, subquery)
	}
}

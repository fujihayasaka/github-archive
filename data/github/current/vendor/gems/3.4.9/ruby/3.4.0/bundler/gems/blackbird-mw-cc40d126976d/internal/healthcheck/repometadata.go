package healthcheck

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	querypb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/shardquery/v1"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/github/go-kvp"
	"github.com/github/go-telemetry/logging"
	"github.com/github/go-telemetry/statting"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"

	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/types"
)

type repoMetadataProber struct{ *Prober }

func newRepoMetadataProber(prober *Prober) *repoMetadataProber {
	return &repoMetadataProber{prober}
}

// Check runs the repo metadata health checks based on the prober's stamp environment.
func (r *repoMetadataProber) Check(ctx context.Context, corpus routing.Corpus, hashValue uint64, cursor string) (*probeResult, error) {
	// Always check for discrepancies between Blackbird's snapshot index and GitHub's repositories table.
	start := time.Now()
	nextHashValue, numReposProbed, healDecisions, err := r.checkBlackbirdReposWithGitHubRepos(ctx, corpus, hashValue)
	if err != nil {
		return nil, err
	}
	statting.DistributionMs(ctx, "prober.repo_metadata.batch_snapshot_check_duration", time.Since(start))

	// If this is a Proxima stamp, additionally check for repositories in GitHub's repositories table that
	// have not been indexed by Blackbird.
	start = time.Now()
	nextCursor := cursor
	if r.stamp != routing.Dotcom {
		cursor, numGitHubReposProbed, proximaHealDecisions, err := r.checkForMissingBlackbirdRepos(ctx, corpus, cursor)
		if err != nil {
			return nil, err
		}
		healDecisions = append(healDecisions, proximaHealDecisions...)
		numReposProbed += numGitHubReposProbed
		nextCursor = cursor
	}
	statting.DistributionMs(ctx, "prober.repo_metadata.batch_github_repo_check_duration", time.Since(start))

	return &probeResult{NextHashValue: nextHashValue, NextCursor: nextCursor, NumReposProbed: numReposProbed, HealDecisions: healDecisions}, nil
}

// batchSize controls the number of Blackbird snapshots and GitHub repositories queried in a single request.
//
// Note: For the blackbird API, this is a suggestion, not a limit.
const batchSize = 1000

// checkForMissingBlackbirdRepos iterates over all GitHub repositories and identifies any repos missing from Blackbird's snapshot index
// and records healing actions for repos that are not indexed by Blackbird. This is only run in proxima.
func (r *repoMetadataProber) checkForMissingBlackbirdRepos(ctx context.Context, corpus routing.Corpus, cursor string) (string, int, []healDecision, error) {
	cluster, err := blackbird.GetClusterWithoutBlobResolution(ctx, r.searchClusters, r.store, r.pager, corpus)
	if err != nil {
		return cursor, 0, nil, err
	}

	ghRepos, nextCursor, err := r.githubClient.GetRepositoriesByCursor(ctx, cursor, batchSize)
	if err != nil {
		return cursor, 0, nil, err
	}

	ghRepoMap := make(map[types.RepoID]bool, len(ghRepos))
	ghRepoIDs := make([]int32, 0, len(ghRepos))
	for _, ghRepo := range ghRepos {
		ghRepoIDs = append(ghRepoIDs, int32(ghRepo.ID))
		ghRepoMap[ghRepo.ID] = true
	}

	queries := make([]*querypb.Query, len(ghRepos))
	for i, ghRepoID := range ghRepoIDs {
		queries[i] = &querypb.Query{
			Kind:            querypb.QueryKind_QUERY_KIND_QUALIFIER,
			Domain:          querypb.Domain_DOMAIN_REPO_ID,
			ValueInt:        []int32{ghRepoID},
			DivorToRetrieve: search.RetrieveAllDocs,
			DivorToScore:    1,
		}
	}
	query := &querypb.Query{
		Kind:            querypb.QueryKind_QUERY_KIND_OR,
		Subqueries:      queries,
		DivorToRetrieve: 1,
		DivorToScore:    1,
	}
	res, err := cluster.SearchSnapshots(ctx, &snapshotpb.SearchSnapshotsRequest{
		QuerySource:       string(search.QuerySourceProber),
		QueryAst:          query,
		TimeoutMillis:     search.DefaultSearchSnapshotTimeoutMillis,
		ServingOffset:     int64(cluster.ServingOffset()),
		EpochId:           uint32(cluster.EpochID()),
		SnapshotsToReturn: uint32(len(ghRepos)),
		EntriesLimit:      1,
	})
	if err != nil {
		return cursor, 0, nil, err
	}

	for _, snapshot := range res.Snapshots {
		if len(snapshot.Entries) != 1 {
			panic(fmt.Sprintf("each snapshot should have 1 entry, got: %+v", snapshot.Entries))
		}
		entry := snapshot.Entries[0]

		_, ok := ghRepoMap[types.RepoID(entry.RepoId)]
		if !ok {
			panic(fmt.Sprintf("snapshot entry for repo not found in GH repo map: %d", entry.RepoId))
		}

		// All snapshot entries (even those with a permanent error) are considered "present" in Blackbird and removed from the ghRepoMap.
		delete(ghRepoMap, types.RepoID(entry.RepoId))
	}

	var healDecisions []healDecision
	for ghRepoID := range ghRepoMap {
		healDecisions = append(healDecisions, healDecision{
			repoID: ghRepoID,
			reason: healRepoNotIndexed,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
		})
	}

	return nextCursor, len(ghRepoIDs), healDecisions, nil
}

// checkBlackbirdReposWithGitHubRepos iterates over a batch of Blackbird repositories, fetches them from GitHub's
// internal API, and checks for discrepancies. It also identifies repos held by Blackbird that have been deleted
// from GitHub. If discrepancies or deleted repos are found, healing decisions are recorded for later action.
func (r *repoMetadataProber) checkBlackbirdReposWithGitHubRepos(ctx context.Context, corpus routing.Corpus, hashValue uint64) (uint64, int, []healDecision, error) {
	cluster, err := blackbird.GetClusterWithoutBlobResolution(ctx, r.searchClusters, r.store, r.pager, corpus)
	if err != nil {
		return hashValue, 0, nil, err
	}

	res, err := cluster.SnapshotsInHashInterval(ctx, hashValue, batchSize)
	if err != nil {
		return hashValue, 0, nil, err
	}

	var healDecisions []healDecision
	blackbirdRepoMap := make(map[types.RepoID]*snapshotpb.SnapshotEntry)
	blackbirdRepoIDs := make([]types.RepoID, 0, len(res.Snapshots))
	for _, snapshot := range res.Snapshots {
		if len(snapshot.Entries) != 1 {
			panic(fmt.Sprintf("each snapshot should have 1 entry, got: %+v", snapshot.Entries))
		}

		entry := snapshot.Entries[0]

		if entry.PermanentError != "" {
			healDecision := r.checkPermanentError(ctx, entry)
			if healDecision != nil {
				healDecisions = append(healDecisions, *healDecision)
			}

			continue
		}

		blackbirdRepoMap[types.RepoID(entry.RepoId)] = entry
		blackbirdRepoIDs = append(blackbirdRepoIDs, types.RepoID(entry.RepoId))
	}

	if len(blackbirdRepoIDs) == 0 {
		return res.NextHash, 0, healDecisions, nil
	}

	ghRepos, err := r.getGitHubRepos(ctx, blackbirdRepoIDs, batchSize)
	if err != nil {
		return hashValue, 0, nil, err
	}

	for _, ghRepo := range ghRepos {
		blackbirdRepo, ok := blackbirdRepoMap[ghRepo.ID]
		if !ok {
			// This should never happen in this context, but if it does, it's a critical error.
			panic(fmt.Sprintf("Returned GitHub repo is not present in source Blackbird snapshot map: %d", ghRepo.ID))
		}

		if healDecision := compareRepoMetadata(blackbirdRepo, ghRepo); healDecision != nil {
			healDecisions = append(healDecisions, *healDecision)
		}

		delete(blackbirdRepoMap, types.RepoID(ghRepo.ID))
	}

	// Next we want to identify discrepancies between the two sets of repo ids retrieved from Blackbird and the GitHub internal API.
	// This helps to identify repositories that have been "purged" or hard deleted in dotcom but are still found in Blackbird's snapshot index.
	for repoID := range blackbirdRepoMap {
		healDecisions = append(healDecisions, healDecision{
			repoID: repoID,
			reason: healRepoNotFound,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
		})
	}

	return res.NextHash, len(blackbirdRepoIDs), healDecisions, nil
}

// checkPermanentError determines if a snapshot entry with a permanent error can
// be healed. It returns a non-nil *healDecision if healing action can be taken.
//
// A permanently errored snapshot entry can be healed if:
//
// - It is a healable error (e.g., we do not attempt to heal repos over system limits)
// - The repo can be fetched from dotcom
// - The default ref can be fetched
//
// TODO: In the future, we may want to heal snapshots based on some time-based
// criteria to avoid trying to heal over and over again.
func (r *repoMetadataProber) checkPermanentError(ctx context.Context, entry *snapshotpb.SnapshotEntry) *healDecision {
	ctx = logging.With(ctx, kvp.Uint("repo_id", uint(entry.RepoId)), kvp.Uint64("entry_id", entry.EntryId), kvp.String("permanent_error", entry.PermanentError))
	logging.Info(ctx, "Permanent error found in snapshot entry")

	// TODO: Remove these strings.Contains checks when the enum is available in all corpora
	// (when <https://github.com/github/blackbird-mw/pull/2947> is merged and a backfill is
	// done everywhere).
	if !(entry.PermanentErrorType == entities.PermanentErrorType_RETRIES_EXHAUSTED || entry.PermanentErrorType == entities.PermanentErrorType_INVALID_DEFAULT_REF || strings.Contains(entry.PermanentError, "retries exhausted") || strings.Contains(entry.PermanentError, "invalid default ref")) {
		return nil
	}

	start := time.Now()
	defer func() {
		statting.DistributionMs(ctx, "prober.repo_metadata.check_permanent_error_duration", time.Since(start))
	}()

	repoID := types.RepoID(entry.RepoId)

	_, err := r.githubClient.GetRepository(ctx, repoID)
	if err != nil {
		logging.Info(ctx, "error fetching permanently errored repository from internal API", kvp.Err(err))
		return nil
	}

	refTip, err := r.gitClient.GetDefaultRef(ctx, repoID)
	if err != nil {
		logging.Info(ctx, "error getting default ref for permanently errored repository ", kvp.Err(err))
		return nil
	}

	if refTip == nil {
		logging.Info(ctx, "nil default ref for permanently errored repository ", kvp.Err(err))
		return nil
	}

	return &healDecision{
		repoID: repoID,
		reason: healRepoPermanentError,
		change: searchpb.RepositoryChanged_ADMIN_REPAIR,
	}
}

func compareRepoMetadata(blackbirdRepo *snapshotpb.SnapshotEntry, ghRepo *github.Repository) *healDecision {
	// When the GitHub repository's `updated_at` timestamp is recent (i.e. within the `servingLagThreshold`),
	// it's likely the related RepositoryChanged event is being processed by ingest, so we should not take any healing action at this time.
	if ghRepo.UpdatedAt.Add(servingLagThreshold).After(time.Now()) {
		return nil
	}

	if types.RepoSeqNo(blackbirdRepo.RepoSeqNo) > ghRepo.RepoSeqNo {
		return nil
	}

	blackbirdNWO := types.NWOFromString(blackbirdRepo.GetNwo())

	if blackbirdNWO.Owner().String() != ghRepo.OwnerLogin {
		return &healDecision{
			repoID: ghRepo.ID,
			reason: healDiscrepancy,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
			discrepancy: &discrepancy{
				field:          "owner_login",
				blackbirdValue: blackbirdNWO.Owner().String(),
				githubValue:    ghRepo.OwnerLogin,
			},
		}
	}

	if blackbirdRepo.GetOwnerId() != ghRepo.OwnerID {
		return &healDecision{
			repoID: ghRepo.ID,
			reason: healDiscrepancy,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
			discrepancy: &discrepancy{
				field:          "owner_id",
				blackbirdValue: strconv.FormatUint(uint64(blackbirdRepo.GetOwnerId()), 10),
				githubValue:    strconv.FormatUint(uint64((ghRepo.OwnerID)), 10),
			},
		}
	}

	if blackbirdNWO.Name() != ghRepo.Name {
		return &healDecision{
			repoID: ghRepo.ID,
			reason: healDiscrepancy,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
			discrepancy: &discrepancy{
				field:          "name",
				blackbirdValue: blackbirdNWO.Name(),
				githubValue:    ghRepo.Name,
			},
		}
	}

	if blackbirdRepo.IsRepoPublic != ghRepo.Public {
		return &healDecision{
			repoID: ghRepo.ID,
			reason: healDiscrepancy,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
			discrepancy: &discrepancy{
				field:          "public",
				blackbirdValue: strconv.FormatBool(blackbirdRepo.IsRepoPublic),
				githubValue:    strconv.FormatBool(ghRepo.Public),
			},
		}
	}

	if blackbirdRepo.GetIsRepoArchived() != ghRepo.Archived {
		return &healDecision{
			repoID: ghRepo.ID,
			reason: healDiscrepancy,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
			discrepancy: &discrepancy{
				field:          "archived",
				blackbirdValue: strconv.FormatBool(blackbirdRepo.GetIsRepoArchived()),
				githubValue:    strconv.FormatBool(ghRepo.Archived),
			},
		}
	}

	if !ghRepo.Experiments.Equal(blackbirdRepo.Experiments) {
		return &healDecision{
			repoID: ghRepo.ID,
			reason: healDiscrepancy,
			change: searchpb.RepositoryChanged_ADMIN_PUSHED,
			discrepancy: &discrepancy{
				field:          "experiments",
				blackbirdValue: fmt.Sprintf("%v", blackbirdRepo.Experiments),
				githubValue:    fmt.Sprintf("%v", ghRepo.Experiments),
			},
		}
	}

	return nil
}

// getGitHubRepos batches repoIDs and fetches them from the internal API.
//
// This handles the case that blackbird happens to return more than the number
// we want to fetch from dotcom in a batch.
func (r *repoMetadataProber) getGitHubRepos(ctx context.Context, repoIDs []types.RepoID, batchSize int) ([]*github.Repository, error) {
	out := make([]*github.Repository, 0, len(repoIDs))

	for {
		if len(repoIDs) == 0 {
			break
		}

		ghRepos, err := r.githubClient.GetRepositoriesByIds(ctx, repoIDs[:min(batchSize, len(repoIDs))])
		if err != nil {
			return nil, err
		}

		out = append(out, ghRepos...)

		repoIDs = repoIDs[min(batchSize, len(repoIDs)):]
	}

	return out, nil
}

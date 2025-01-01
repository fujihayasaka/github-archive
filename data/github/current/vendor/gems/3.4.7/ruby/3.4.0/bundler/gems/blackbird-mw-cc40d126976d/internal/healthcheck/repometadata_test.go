package healthcheck

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/github/blackbird/crates/client/pkg/blackbird"
	snapshotpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/snapshot/v1"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/db/dbfakes"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/gitaccess/gitaccessfakes"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

func TestDiscrepanciesFoundBetweenBlackbirdAndGitHubRepoMetadata(t *testing.T) {
	dotcomStamp := routing.Dotcom
	proximaStamp := routing.ProdWEU01

	repoGenerator := func(id uint32, repoSeqNo types.RepoSeqNo) *github.Repository {
		return &github.Repository{
			ID:         types.RepoID(id),
			OwnerID:    id,
			OwnerLogin: fmt.Sprintf("owner%d", id),
			Name:       fmt.Sprintf("repo%d", id),
			Public:     true,
			RepoSeqNo:  repoSeqNo,
		}
	}

	repoSeqNo := types.RepoSeqNo(1)

	setupMocks := func(getReposByIDsRepos []*github.Repository, snapshotsInHashIntervalSnapshots []*snapshotpb.Snapshot, getReposByCursorRepos []*github.Repository, searchSnapshots []*snapshotpb.Snapshot, f func(*github.Repository, *snapshotpb.Snapshot), corpus routing.Corpus) (*routing.SearchClusters, github.InternalAPIClient, *repo.Publisher) {
		// fakeSearchAPI returns the mocked Blackbird snapshots via its SnapshotsInHashIntervalReturns stub.
		fakeSearchAPI := &mocks.FakeSearchAPI{}
		fakeSearchAPI.SnapshotsInHashIntervalReturns(&snapshotpb.SnapshotsInHashIntervalResponse{Snapshots: snapshotsInHashIntervalSnapshots}, nil)
		fakeSearchAPI.SearchSnapshotsReturns(&snapshotpb.SearchSnapshotsResponse{Snapshots: searchSnapshots}, nil)

		fakeClient := &mocks.FakeBlackbirdClient{}
		fakeClient.IsServingReturns(true)
		fakeClient.IsIndexingPausedReturns(false)
		fakeClient.RoutesReturns(blackbird.Routes{
			ServingTs: time.Now().UnixMilli(),
			Hosts:     [][]*blackbird.IndexHost{{&blackbird.IndexHost{SearchClient: fakeSearchAPI}}},
		})

		clients := map[routing.Corpus]blackbird.Client{}
		clients[corpus] = fakeClient

		// searchClusters contains a clients map that contains a single mocked Blackbird client,
		// and that mocked Blackbird client owns the mocked search API that returns the mocked Blackbird snapshots.
		searchClusters := routing.NewSearchClusters(clients)

		// githubClient returns the mocked GitHub repositories via its GetRepositoriesByIdsReturns stub.
		githubClient := &githubfakes.FakeInternalAPIClient{}

		// GetRepositoriesByIds and GetRepository return repos from getReposByIDsRepos, but the caller MUST send an ID in the list
		githubClient.GetRepositoriesByIdsStub = func(ctx context.Context, repoIDs []types.RepoID) ([]*github.Repository, error) {
			out := []*github.Repository{}
			for _, repoID := range repoIDs {
				for _, repo := range getReposByIDsRepos {
					if repoID == repo.ID {
						out = append(out, repo)
					}
				}
			}
			return out, nil
		}
		githubClient.GetRepositoryStub = func(ctx context.Context, repoID types.RepoID) (*github.Repository, error) {
			for _, repo := range getReposByIDsRepos {
				if repoID == repo.ID {
					return repo, nil
				}
			}

			return nil, github.ErrRepoNotFound
		}
		githubClient.GetRepositoriesByCursorReturns(getReposByCursorRepos, "", nil)

		// syncProducer and repoPublisher are used to verify that the prober takes the expected healing actions.
		repoPublisher := repo.NewPublisher(&mocks.FakeSyncProducer{}, 1)

		for i := 0; i < len(getReposByIDsRepos); i++ {
			if len(snapshotsInHashIntervalSnapshots) > i {
				f(getReposByIDsRepos[i], snapshotsInHashIntervalSnapshots[i])
			}
		}

		return searchClusters, githubClient, repoPublisher
	}

	var tests = []struct {
		name                             string
		stamp                            routing.Stamp
		discrepancyGenerator             func(*github.Repository, *snapshotpb.Snapshot)
		getRepositoryByIDsRepos          []*github.Repository // list of repos that can be returned from GetRepositoriesByIds and GetRepository
		snapshotsInHashIntervalSnapshots []*snapshotpb.Snapshot
		getRepositoriesByCursorRepos     []*github.Repository
		searchSnapshots                  []*snapshotpb.Snapshot
		permanentErrorRefTip             *gitaccess.RefTip // RefTip returned from GetDefaultRef when snapshot has healable permanent error
		permanentErrorRefTipError        error             // error returned from GetDefaultRef when snapshot has healable permanent error
		expectedHealDecisions            int
		expectedHealReason               string
		expectedField                    string
	}{
		{
			name:                             "returns no healing decision when no discrepancies are found",
			stamp:                            dotcomStamp,
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, /* no discrepancies */
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            0,
		},

		{
			name:  "returns no healing decision when discrepancies are present but GitHub repo's `updated_at` timestamp is within ambiguity threshold",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.Name = "new_name"      // Discrepancy: GitHub repo's name is different from Blackbird's.
				repo.UpdatedAt = time.Now() // Ambiguity: GitHub repo's `updated_at` timestamp is within ambiguity threshold.
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            0,
		},

		{
			name:  "returns no healing decision when discrepancies are present but Blackbird's RepoSeqNo is newer than GitHub's",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.Name = "new_name" // Discrepancy: GitHub repo's name is different from Blackbird's.
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, types.RepoSeqNo(uint64(repoSeqNo)+1), "")},
			expectedHealDecisions:            0,
		},

		{
			name:                             "returns healing decision when GitHub repos are not found, but exist in Blackbird's snapshot index",
			stamp:                            dotcomStamp,
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			getRepositoryByIDsRepos:          []*github.Repository{},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")}, // Blackbird has repositories not found in GitHub and means the repositories were deleted from GitHub, and should be removed from Blackbird.
			expectedHealDecisions:            1,
			expectedHealReason:               healRepoNotFound,
		},

		{
			name:  "returns healing decision when experiments data is mismatched",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.Experiments = map[string]string{"experiments": "blackbird_enable_code_embedding"}
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			getRepositoriesByCursorRepos:     []*github.Repository{repoGenerator(1, repoSeqNo)},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			expectedHealDecisions:            1,
			expectedField:                    "experiments",
			expectedHealReason:               healDiscrepancy,
		},

		{
			name:                             "returns healing decision when Blackbird's snapshot index is missing GitHub repos (proxima only)",
			stamp:                            proximaStamp,
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},               // Not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},  // Not significant for this condition.
			getRepositoriesByCursorRepos:     []*github.Repository{repoGenerator(1, repoSeqNo)},
			searchSnapshots:                  []*snapshotpb.Snapshot{}, // Missing snapshots in Proxima.
			expectedHealDecisions:            1,
			expectedHealReason:               healRepoNotIndexed,
		},

		{
			name:                             "returns no healing decision when Blackbird's snapshot index does not contain a deleted GitHub repo (proxima only)",
			stamp:                            proximaStamp,
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			getRepositoryByIDsRepos:          []*github.Repository{},                                          // Not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{},                                        // Not significant for this condition.
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			expectedHealDecisions:            0,
		},

		{
			name:  "returns healing decision when owner login discrepancy is found",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.OwnerLogin = "new_owner" // Discrepancy: GitHub owner login is different from Blackbird owner login.
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            1,
			expectedHealReason:               healDiscrepancy,
			expectedField:                    "owner_login",
		},

		{
			name:  "returns healing decision when owner id discrepancy is found",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.OwnerID += 1 // Discrepancy: GitHub owner id is different from Blackbird owner id.
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            1,
			expectedHealReason:               healDiscrepancy,
			expectedField:                    "owner_id",
		},

		{
			name:  "returns healing decision when repo name discrepancy is found",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.Name = "new_name" // Discrepancy: GitHub repo name is different from Blackbird repo name.
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            1,
			expectedHealReason:               healDiscrepancy,
			expectedField:                    "name",
		},

		{
			name:  "returns healing decision when public discrepancy is found",
			stamp: dotcomStamp,
			discrepancyGenerator: func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {
				repo.Public = !repo.Public // Discrepancy: GitHub repo public status is different from Blackbird repo public status.
			},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            1,
			expectedHealReason:               healDiscrepancy,
			expectedField:                    "public",
		},

		{
			name:                             "returns healing action when github repo deleted and snapshot entry is found (proxima and dotcom)",
			stamp:                            proximaStamp,                                                    // This ensures this test case applies for both proxima and dotcom.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			getRepositoryByIDsRepos:          []*github.Repository{},
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			expectedHealDecisions:            1,
			expectedHealReason:               healRepoNotFound,
		},

		{
			name:                             "returns no healing action when snapshot entry has a permanent error that is not correctable",
			stamp:                            proximaStamp,                                                    // This ensures that the snapshot entry is not considered for healing in both dotcom and proxima.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "not fixable")},
			getRepositoriesByCursorRepos:     []*github.Repository{repoGenerator(1, repoSeqNo)},
			searchSnapshots:                  []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "")},
			expectedHealDecisions:            0,
		},

		{
			name:                             "returns healing action when snapshot entry has a 'retries exhausted' permanent error and the repository is healable",
			stamp:                            proximaStamp,                                                    // This ensures this test case applies for both proxima and dotcom.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "retries exhausted")},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			permanentErrorRefTip:             &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)},
			expectedHealDecisions:            1,
			expectedHealReason:               healRepoPermanentError,
		},

		{
			name:                             "returns healing action when snapshot entry has a 'invalid default ref' permanent error and the repository is healable",
			stamp:                            proximaStamp,                                                    // This ensures this test case applies for both proxima and dotcom.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "invalid default ref")},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			permanentErrorRefTip:             &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)},
			expectedHealDecisions:            1,
			expectedHealReason:               healRepoPermanentError,
		},

		{
			name:                             "returns no healing action when snapshot entry has a healable permanent error but the repository is not found",
			stamp:                            proximaStamp,                                                    // This ensures this test case applies for both proxima and dotcom.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "retries exhausted")},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(2, repoSeqNo)}, // different repo ID
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			expectedHealDecisions:            0,
		},

		{
			name:                             "returns no healing action when snapshot entry has a healable permanent error but the ref tip is nil",
			stamp:                            proximaStamp,                                                    // This ensures this test case applies for both proxima and dotcom.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "retries exhausted")},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			permanentErrorRefTip:             nil,
			expectedHealDecisions:            0,
		},

		{
			name:                             "returns no healing action when snapshot entry has a healable permanent error but there is an error getting the ref tip",
			stamp:                            proximaStamp,                                                    // This ensures this test case applies for both proxima and dotcom.
			discrepancyGenerator:             func(repo *github.Repository, snapshot *snapshotpb.Snapshot) {}, // Discrepancies are not significant for this condition.
			snapshotsInHashIntervalSnapshots: []*snapshotpb.Snapshot{snapshotGenerator(t, 1, repoSeqNo, "retries exhausted")},
			getRepositoryByIDsRepos:          []*github.Repository{repoGenerator(1, repoSeqNo)},
			getRepositoriesByCursorRepos:     []*github.Repository{},
			searchSnapshots:                  []*snapshotpb.Snapshot{},
			permanentErrorRefTipError:        errors.New("boom"),
			expectedHealDecisions:            0,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			ctx := context.Background()
			corpus := helpers.Corpus(t)
			cursor := "1"
			store := &dbfakes.FakeStore{}
			cache := cache.NewInMemory()
			gitClient := &gitaccessfakes.FakeClient{}
			gitClient.GetDefaultRefReturns(test.permanentErrorRefTip, test.permanentErrorRefTipError)

			searchClusters, githubClient, repoPublisher := setupMocks(test.getRepositoryByIDsRepos, test.snapshotsInHashIntervalSnapshots, test.getRepositoriesByCursorRepos, test.searchSnapshots, test.discrepancyGenerator, corpus)
			indexerClusters := helpers.IndexerClusters(t)
			prober := NewProber(store, cache, gitClient, test.stamp, searchClusters, indexerClusters, &mocks.FakeSaramaClient{}, githubClient, repoPublisher, nil /* copilotClient */, helpers.MockDelayedTimestampReader(t))
			repoMetadataProber := newRepoMetadataProber(prober)

			checkResult, err := repoMetadataProber.Check(ctx, corpus, 0, cursor)
			require.NoError(t, err)
			require.Equal(t, test.expectedHealDecisions, len(checkResult.HealDecisions))
			if test.expectedHealDecisions > 0 {
				require.Equal(t, test.expectedHealReason, checkResult.HealDecisions[0].reason)
				if checkResult.HealDecisions[0].discrepancy != nil {
					require.Equal(t, test.expectedField, checkResult.HealDecisions[0].discrepancy.field)
				}
			}
		})
	}
}

func Test_getGitHubRepos(t *testing.T) {
	githubClient := &githubfakes.FakeInternalAPIClient{}
	githubClient.GetRepositoriesByIdsStub = func(ctx context.Context, repoIDs []types.RepoID) ([]*github.Repository, error) {
		out := []*github.Repository{}
		for _, repoID := range repoIDs {
			out = append(out, &github.Repository{ID: repoID})
		}
		return out, nil
	}
	prober := NewProber(nil, nil, nil, routing.Dotcom, nil, nil, &mocks.FakeSaramaClient{}, githubClient, nil, nil, nil)
	repoMetadataProber := newRepoMetadataProber(prober)
	repos, err := repoMetadataProber.getGitHubRepos(context.Background(), []types.RepoID{1, 2, 3}, 2)
	require.NoError(t, err)
	require.Len(t, repos, 3)
	require.Equal(t, 2, githubClient.GetRepositoriesByIdsCallCount())

	expected := []types.RepoID{1, 2, 3}
	actual := []types.RepoID{}
	for _, repo := range repos {
		actual = append(actual, repo.ID)
	}
	require.ElementsMatch(t, expected, actual)
}

func snapshotGenerator(t *testing.T, id uint32, repoSeqNo types.RepoSeqNo, permanentError string) *snapshotpb.Snapshot {
	t.Helper()
	return &snapshotpb.Snapshot{
		Entries: []*snapshotpb.SnapshotEntry{
			{
				RepoId:         id,
				OwnerId:        id,
				Nwo:            fmt.Sprintf("owner%d/repo%d", id, id),
				IsRepoPublic:   true,
				RepoSeqNo:      uint64(repoSeqNo),
				PermanentError: permanentError,
			},
		},
	}
}

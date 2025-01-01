// Package integration defines system-level integration tests for blackbird-mw.
//
//   - Each test should create an epoch so that it's siloed from other tests.
//   - Integration test should only use public (http) APIs. A test should never
//     e.g. directly query shards or run an ingest worker.
//   - There are two sample repositories available (seeded in script/setup):
//     repoID 1: git-tfs/git-tfs.github.com
//     repoID 2: go-git/go-git-fixtures
//
// You can run script/integration-tests directly (this is what CI does). To
// run individual integration tests:
//
// 1. Run the docker compose environment:
// script/setup --spokes
//
// 2. Run the integration tests:
// RUN_INT_TESTS=True BLACKBIRD_MW_ENV=test go test -p 1 -v -run Test_End2End ./internal/test/integration/*
//
// NOTE: If you change any Go code, you'll need to re-build and restart those containers:
// docker compose -f docker-compose.yml -f docker-compose.mw.yml up --build -d
package integration

import (
	"context"
	"database/sql"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/github/blackbird/clients/go/semantic"
	semanticpb "github.com/github/blackbird/clients/go/semantic/v1"
	bb "github.com/github/blackbird/crates/client/pkg/blackbird"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	"github.com/github/blackbird/crates/core/pkg/epoch"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/github"
	adminPb "github.com/github/blackbird-mw/internal/proto/admin/v1"
	queryPb "github.com/github/blackbird-mw/internal/proto/query/v1"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/search/blackbird"
	"github.com/github/blackbird-mw/internal/test/fakegithub"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
	"github.com/github/blackbird-mw/internal/utils"
	"github.com/github/blackbird-mw/schemas"
)

const (
	// The number of shards in the blackbird cluster. This is coupled with the
	// cluster setup in Docker Compose and is used to create document topics at
	// runtime.
	numBlackbirdShards = 2

	// NB: We use hubot's real user_id so that copilot license checks work in the integration tests (which call out to capi to
	// compute embeddings).
	hubotUserID = 480938
)

var (
	tenantMode = os.Getenv("BLACKBIRD_MW_MODE") == "tenant"
	epochMode  = parseEpochMode(os.Getenv("BLACKBIRD_MW_EPOCH_MODE"))

	// This repo is used for testing the handling of deleted repos in ingest.
	deletedRepo = github.Repository{
		ID:          1000,
		NetworkID:   1,
		OwnerID:     1,
		OwnerLogin:  "github",
		Name:        "deleted-repo",
		Public:      true,
		DiskUsage:   1,
		Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
	}

	// Used by epoch branching tests to ensure the indexer can process
	// new pushes after the branching is done.
	epochBranchingRepo = github.Repository{
		ID:          fakegithub.EpochBranchingRepoID,
		NetworkID:   types.NetworkID(fakegithub.EpochBranchingRepoID),
		OwnerID:     1482403,
		OwnerLogin:  "mbellani",
		Name:        "code-search-test",
		Public:      true,
		DiskUsage:   1,
		UpdatedAt:   time.Now(),
		Experiments: experiments.Experiments{experiments.EnableCodeEmbedding: experiments.Enabled},
	}
)

func Test_End2End(t *testing.T) {
	helpers.IntegrationTest(t)

	corpus, err := routing.CorpusFromString(os.Getenv("BLACKBIRD_MW_OUTPUT_CORPUS"))
	require.NoError(t, err)

	ctx := context.Background()
	fakeGitHub := helpers.FakeGitHubClient(t)
	fakeGitHub.Reset()

	// 1. Do an empty backfill and validate that we can query
	epochID, latestOffset := coldstartBackfill(t, corpus, fakeGitHub)
	query(t, "repo_id:1 path:CNAME", epochID, 1)

	// 2. Do an MST-driven backfill
	epochID, latestOffset = mstBackfill(t, ctx, corpus, epochID, latestOffset, fakeGitHub)

	// 3. Validate
	t.Run("indexing a deleted repo marks it deleted", func(t *testing.T) {
		client := helpers.BlackbirdAdminClient(t)
		resp, err := client.GetRepoStatus(ctx, &adminPb.GetRepoStatusRequest{
			RepoId: uint32(deletedRepo.ID),
			Corpus: corpus.String(),
		})
		require.NoError(t, err)
		require.NotNil(t, resp.DeletedAt)
	})

	// 4. Capture a timestamp that will be used when testing epoch branching
	_, branchTs := getServingOffsetAndTs(t, corpus)

	t.Run("repo scoped query", func(t *testing.T) {
		if epoch.EpochFeaturesLexical.SupportedBy(epochMode) {
			query(t, "repo_id:1 body", epochID, 4)
		}
		// Assert all paths we expected to be in the index for: https://github.com/git-tfs/git-tfs.github.com
		query(t, "repo_id:1 path:_includes/download_button.html", epochID, 1)
		query(t, "repo_id:1 path:_layouts/default.htm", epochID, 1)
		query(t, "repo_id:1 path:_layouts/markdown.htm", epochID, 1)
		query(t, "repo_id:1 path:_sass/git-tfs.scss", epochID, 1)
		query(t, "repo_id:1 path:images/apple-touch-icon-114x114.png", epochID, 0) // NB: detected as binary
		query(t, "repo_id:1 path:images/apple-touch-icon-72x72.png", epochID, 0)   // NB: detected as binary
		query(t, "repo_id:1 path:images/apple-touch-icon.png", epochID, 0)         // NB: detected as binary
		query(t, "repo_id:1 path:images/favicon.ico", epochID, 0)                  // NB: detected as binary
		query(t, "repo_id:1 path:images/graphy.png", epochID, 0)                   // NB: detected as binary
		query(t, "repo_id:1 path:javascripts/tabs.js", epochID, 1)
		query(t, "repo_id:1 path:stylesheets/base.css", epochID, 1)
		query(t, "repo_id:1 path:stylesheets/git-tfs.css", epochID, 0) // NB: detected as generated (it is)
		query(t, "repo_id:1 path:stylesheets/layout.css", epochID, 1)
		query(t, "repo_id:1 path:stylesheets/skeleton.css", epochID, 1) //NB: detected as generated by enry but it's no longer excluded from the index.
		query(t, "repo_id:1 path:.rvmrc", epochID, 1)
		query(t, "repo_id:1 path:CNAME", epochID, 1)
		query(t, "repo_id:1 path:Gemfile", epochID, 2)
		query(t, "repo_id:1 path:Rakefile", epochID, 1)
		query(t, "repo_id:1 path:_config.yml", epochID, 1)
		query(t, "repo_id:1 path:config.rb", epochID, 1)
		query(t, "repo_id:1 path:index.md", epochID, 1)
		query(t, "repo_id:1 path:robots.txt", epochID, 1)
	})

	t.Run("repo scoped embeddings query", func(t *testing.T) {
		if !epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("embeddings queries are not supported in lexical mode")
		}
		query(t, "repo_id:2 prompt:\"how do i add a new fixture?\"", epochID, 2, "prompt_qualifier=1")
	})

	t.Run("repo scoped embeddings query with rust mw", func(t *testing.T) {
		if epochMode != epoch.EpochModeEmbeddingsGraph {
			t.Skip("embeddings queries against the rust mw only run for embeddings graph mode")
		}
		waitForSemanticServingOffsetToExceed(t, epochID, latestOffset)
		// NB: Only repo: is supported. TODO: support repo_id: too?
		semanticQuery(t, "how do i add a new fixture?", "repo:go-git/go-git-fixtures", epochID, 35)
	})

	t.Run("repo scoped bm25 query", func(t *testing.T) {
		if !epoch.EpochFeaturesBM25.SupportedBy(epochMode) {
			t.Skip("bm25 queries are not supported in embeddings mode")
		}
		query(t, "repo_id:2 prompt:\"how do i add a new fixture?\"", epochID, 5, "prompt_qualifier=bm25")
	})

	t.Run("query rewriting with snapshots", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// repo qualifiers + is: qualifier
		query(t, "repo:git-tfs/git-tfs.github.com is:vendored", epochID, 2)
		// satisfiable
		query(t, "repo:git-tfs/git-tfs.github.com AND (repo:git-tfs/git-tfs.github.com OR repo:go-git/go-git-fixtures)", epochID, 18)
		// with org qualifier
		query(t, "org:git-tfs hide", epochID, 1)
		// unsatisfiable
		client := helpers.BlackbirdQueryClient(t)
		queryRequest := &queryPb.QueryRequest{
			Query:   "repo:git-tfs/git-tfs.github.com repo:go-git/go-git-fixtures",
			EpochId: uint32(epochID),
			Tenant:  fakegithub.Tenant(),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		}
		response, err := client.Query(ctx, queryRequest)
		require.NoError(t, err)
		require.Equal(t, 1, len(response.QueryErrors))
		require.Equal(t, queryPb.ErrorType_ERROR_TYPE_QUERY_PARSING_FATAL, response.QueryErrors[0].Type)
		require.Equal(t, "condition is unsatisfiable", response.QueryErrors[0].Message)
	})

	t.Run("symbol and language queries", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		query(t, "repo_id:4 def:CommitDb", epochID, 1)
		query(t, "repo_id:4 lang:Markdown", epochID, 1)
	})

	t.Run("multi-repo scoped query", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		query(t, "(repo_id:1 OR repo_id:2) hide", epochID, 1)
	})

	t.Run("org scoped query", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		query(t, "org:git-tfs hide", epochID, 1)
	})

	t.Run("vendored and generated queries", func(t *testing.T) {
		query(t, "is:vendored", epochID, 48)
		query(t, "is:generated", epochID, 0) // There aren't any generated docs in our current int test corpus.
	})

	t.Run("search in delta indexed parent repository", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// NOTE: This is based on experimentation and changes based on the sharding strategy.
		indexedMojomboGritBlobs := 214
		if epoch.EpochFeaturesDedupingByContent.SupportedBy(epochMode) {
			indexedMojomboGritBlobs = 162
		}
		count(t, fakegithub.MojomboGritRepoID, epochID, indexedMojomboGritBlobs)

		// This text should match a document in both mojombo/grit and github/grit, because they both contain a blob with this text
		query(t, `repo_id:4 "+start+ is the branch/commit name"`, epochID, 1)

		// This text should match a blob that from mojombo/grit that is unchanged in github/grit
		query(t, `repo_id:4 "Add remote branch references (Grit::Remote)"`, epochID, 1)

		// This text should match a document only in mojombo/grit, the typo fix was reverted in github/grit
		query(t, `repo_id:4 "+since+ is a string representing a date/time"`, epochID, 1)

		// This text should match a document only in mojombo/grit
		query(t, `repo_id:4 "Grit is no longer maintained"`, epochID, 1)

		// This text should match a document only in github/grit and should return 0 results here
		query(t, `repo_id:4 "Filenames can have weird characters"`, epochID, 0)
	})

	t.Run("search in delta indexed child repository", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// NOTE: This is based on experimentation.
		//
		// From the ingest logs, mojombo/grit publishes 147 documents and github/grit publishes 57 documents.
		// When run in lexical mode, this test returns 187 documents.
		// When in hybrid mode, this test returns 247 documents.
		indexedGithubGritBlobs := 247
		if epoch.EpochFeaturesDedupingByContent.SupportedBy(epochMode) {
			indexedGithubGritBlobs = 187
		}
		count(t, fakegithub.GitHubGritRepoID, epochID, indexedGithubGritBlobs)

		// This text should return a result that only exists in github/grit
		query(t, `repo_id:5 "Filenames can have weird characters"`, epochID, 1)

		// This text should match a document that only exists in mojombo/grit and should return 0 results here
		query(t, `repo_id:5 "Grit is no longer maintained"`, epochID, 0)

		// This text should match a document that is inherited from mojombo/grit
		query(t, `repo_id:5 "+start+ is the branch/commit name"`, epochID, 1)

		// This text should match a blob that is unchanged from mojombo/grit
		query(t, `repo_id:5 "Add remote branch references (Grit::Remote)"`, epochID, 1)

		// This text should only match a document in github/grit, the typo was fixed and then reverted
		query(t, `repo_id:5 "+since+ is a string represeting a date/time"`, epochID, 1)
		query(t, `repo_id:5 "+since+ is a string representing a date/time"`, epochID, 0)
	})

	t.Run("global search", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// This text should match a document that only exists in mojombo/grit
		query(t, `"Grit is no longer maintained"`, epochID, 1)

		// This text should only match a document in github/grit, the typo was fixed and then reverted
		query(t, `"+since+ is a string represeting a date/time"`, epochID, 1)

		// This text should match a document in both mojombo/grit and github/grit, because they both contain (different) blobs with this text
		query(t, `"+start+ is the branch/commit name"`, epochID, 2)

		// This text should match a blob that from mojombo/grit that is unchanged in github/grit
		// NOTE: Only 1 document is returned. It has multiple locations.
		query(t, `"Add remote branch references (Grit::Remote)"`, epochID, 1)
	})

	t.Run("legacy search emulation", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// Tests a simple scoped search
		legacyQuery(t, "repo_id:1 body", 4)

		// Tests the weird legacy search path:/ behavior with filename matching
		legacyQuery(t, "repo_id:1 path:/ filename:config.rb", 1)

		// Tests matching only in path (and global search)
		legacyQuery(t, "robots in:path", 1)
	})

	t.Run("legacy search pagination", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		q := "def"
		client := helpers.BlackbirdQueryClient(t)
		response, err := client.LegacyQuery(ctx, &queryPb.LegacyQueryRequest{
			Query:          q,
			PageNumber:     0,
			ResultsPerPage: 2,
			Actor:          generateActor(123, fakegithub.AllAccessToken),
		})
		require.NoError(t, err)
		require.Empty(t, response.QueryErrors)
		require.Len(t, response.Results, 2, "query %q page 0 returned unexpected number of results: %s", q, debugResults(t, response.Results))

		response, err = client.LegacyQuery(ctx, &queryPb.LegacyQueryRequest{
			Query:          q,
			PageNumber:     1,
			ResultsPerPage: 2,
			Actor:          generateActor(123, fakegithub.AllAccessToken),
		})
		require.NoError(t, err)
		require.Empty(t, response.QueryErrors)
		require.Len(t, response.Results, 2, "query %q page 1 returned unexpected number of results: %s", q, debugResults(t, response.Results))

		response, err = client.LegacyQuery(ctx, &queryPb.LegacyQueryRequest{
			Query:          q,
			PageNumber:     2,
			ResultsPerPage: 2,
			Actor:          generateActor(123, fakegithub.AllAccessToken),
		})
		require.NoError(t, err)
		require.Empty(t, response.QueryErrors)
		require.NotEmpty(t, response.Results, "query %q page 2 returned no results: %s", q, debugResults(t, response.Results))
	})

	t.Run("sim-search github/grit", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		ctx := context.Background()
		try := 0
		for {
			// TODO: The admin services dsa client takes a moment to catchup so this
			// fails at first. `backfill` only ensures that the mw-query service is
			// successfully serving a particular epoch+offset.
			client := helpers.BlackbirdAdminClient(t)
			response, err := client.GetSimilarRepos(ctx, &adminPb.GetSimilarReposRequest{
				RepoNwo:            repoNWOWithTenant("github", "grit"), // The admin service operates on repo owner login names containing tenant shortcode suffixes.
				Corpus:             corpus.String(),
				NumSnapshots:       5,
				EntriesPerSnapshot: 1,
				EpochId:            uint32(epochID),
			})
			if err != nil && try < 5 {
				fmt.Printf("  [try=%d] error getting similar repos: %v\n", try, err)
				time.Sleep(5 * time.Second)
				try++
				continue
			}

			require.NoError(t, err)

			nwos := []string{}
			ids := []types.RepoID{}
			for _, simRepo := range response.SimilarRepos {
				nwos = append(nwos, simRepo.RepoNwo)
				ids = append(ids, types.RepoID(simRepo.RepoId))
			}

			require.ElementsMatch(t, []string{
				repoNWOWithTenant("mojombo", "grit"),
				repoNWOWithTenant("github", "grit"),
			}, nwos)
			require.ElementsMatch(t, []types.RepoID{fakegithub.MojomboGritRepoID, fakegithub.GitHubGritRepoID}, ids)
			break
		}
	})

	t.Run("probe delta indexed repositories", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		ctx := context.Background()

		client := helpers.BlackbirdAdminClient(t)

		response, err := client.ProbeRepo(ctx, &adminPb.ProbeRepoRequest{
			Corpus:  corpus.String(),
			RepoNwo: repoNWOWithTenant("github", "grit"),
		})
		require.NoError(t, err)

		require.Empty(t, response.Extra)
		require.Empty(t, response.Missing)
		require.EqualValues(t, 247, response.Verified) // NOTE: Verified experimentally

		response, err = client.ProbeRepo(ctx, &adminPb.ProbeRepoRequest{
			Corpus:  corpus.String(),
			RepoNwo: repoNWOWithTenant("mojombo", "grit"),
		})
		require.NoError(t, err)

		require.Empty(t, response.Extra)
		require.Empty(t, response.Missing)
		require.EqualValues(t, 214, response.Verified) // NOTE: Verified experimentally
	})

	client := helpers.BlackbirdQueryClient(t)

	t.Run("global query", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		response, err := client.Query(ctx, &queryPb.QueryRequest{
			Query:   "git",
			EpochId: uint32(epochID),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		})
		require.NoError(t, err)
		// NB: Since we can't fully flush documents, this test is hard to write so we just assert there are at least 5 of them.
		require.GreaterOrEqual(t, len(response.Documents), 5, "unexpected number of documents: %s", debugDocuments(t, response.Documents))
		require.Empty(t, response.QueryErrors)
	})

	t.Run("invalid epoch", func(t *testing.T) {
		response, err := client.Query(ctx, &queryPb.QueryRequest{
			Query:   "body",
			EpochId: uint32(epochID) + 1,
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		})
		require.EqualError(t, err, fmt.Sprintf("twirp error internal: failed to auto select a cluster: invalid epoch_id %d", epochID+1))
		require.Nil(t, response)
	})

	t.Run("incremental index on push", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// No results for this query (the name of the test)
		query(t, t.Name(), epochID, 0)

		// Make a simple commit
		commitAndPush(t, "README.md", t.Name()+"\n")

		// Force the next documents to have a LogAppendTime in the future
		time.Sleep(1 * time.Second)

		// Trigger an incremental index of this repo
		ctx := context.Background()
		client := helpers.BlackbirdAdminClient(t)
		_, err := client.IndexRepo(ctx, &adminPb.IndexRepoRequest{
			RepoNwo: repoNWOWithTenant("git-tfs", "git-tfs.github.com"),
		})
		require.NoError(t, err)

		// NB: Give the mw-ingest service a chance to pick up this incremental
		// change and create an ingest record.
		time.Sleep(2 * time.Second)

		// Wait for ingest to complete
		latestOffset = waitForIngestToFinish(t, corpus, fakegithub.GitTFSRepoID, epochID, latestOffset)

		// Now there should be 1 result
		query(t, t.Name(), epochID, 1)
	})

	t.Run("incremental index on force push", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// Trigger an initial index of this repo.
		ctx := context.Background()
		client := helpers.BlackbirdAdminClient(t)

		// Establish baseline result for this repo-scoped query.
		query(t, `repo_id:6 "README"`, epochID, 1)
		// There should be no results for a global query using this test name.
		query(t, t.Name(), epochID, 0)

		// Amend the head commit and force push to the remote.
		amendHeadCommit(t, "README.md", t.Name()+"\n")

		// Force the next documents to have a LogAppendTime in the future.
		time.Sleep(1 * time.Second)

		// Trigger an incremental index of this repo whose previous HEAD commit is no longer reachable.
		_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoId: uint32(fakegithub.JavaTestRepoID)})
		require.NoError(t, err)

		// NB: Give the mw-ingest service a chance to pick up this incremental
		// change and create an ingest record.
		time.Sleep(2 * time.Second)

		latestOffset = waitForIngestToFinish(t, corpus, fakegithub.JavaTestRepoID, epochID, latestOffset)

		// Now there should be 1 result for this global query for the force pushed commit.
		query(t, t.Name(), epochID, 1)
	})

	t.Run("visibility change", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		repo := fakeGitHub.RepositoryForID(fakegithub.MojomboGritRepoID)

		// NOTE: After backfilling we can query by the original public status
		query := &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d trait:public_repo "+start+ is the branch/commit name"`, repo.ID),
			EpochId: uint32(epochID),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		}
		response, err := client.Query(ctx, query)
		require.NoError(t, err)
		require.Equal(t, 1, len(response.Documents), "unauthorized query %q returned documents: %s", query.Query, debugDocuments(t, response.Documents))
		require.Empty(t, response.QueryErrors)

		repo.Public = false
		fakeGitHub.UpdateRepository(fakegithub.MojomboGritRepoID, repo)

		adminClient := helpers.BlackbirdAdminClient(t)
		_, err = adminClient.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoNwo: repo.NWO()})
		require.NoError(t, err)

		latestOffset = waitForIngestToFinish(t, corpus, fakegithub.MojomboGritRepoID, epochID, latestOffset)

		// NOTE: After incremental ingest, we can query without a trait, but since the user can't see the repo there are no results.
		query = &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d "+start+ is the branch/commit name"`, repo.ID),
			EpochId: uint32(epochID),
			Actor:   generateActor(321, "no-access-token"),
		}

		response, err = client.Query(ctx, query)
		require.NoError(t, err)
		require.Equal(t, 0, len(response.Documents), "unauthorized query %q returned documents: %s", query.Query, debugDocuments(t, response.Documents))

		// NOTE: An authorized request finds the document when not using a trait
		query = &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d "+start+ is the branch/commit name"`, repo.ID),
			EpochId: uint32(epochID),
			Actor:   generateActor(456, fakegithub.AllAccessToken),
		}

		response, err = client.Query(ctx, query)
		require.NoError(t, err)
		require.Empty(t, response.QueryErrors)
		require.Equal(t, 1, len(response.Documents), "authorized query %q returned unexpected number of documents: %s", query.Query, debugDocuments(t, response.Documents))
		require.False(t, response.Documents[0].Locations[0].IsRepoPublic)

		// NOTE: An authorized request finds the document when using a trait
		query = &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d NOT trait:public_repo "+start+ is the branch/commit name"`, repo.ID),
			EpochId: uint32(epochID),
			Actor:   generateActor(456, fakegithub.AllAccessToken),
		}

		response, err = client.Query(ctx, query)
		require.NoError(t, err)
		require.Empty(t, response.QueryErrors)
		require.Equal(t, 1, len(response.Documents), "authorized query %q returned unexpected number of documents: %s", query.Query, debugDocuments(t, response.Documents))
		require.False(t, response.Documents[0].Locations[0].IsRepoPublic)
	})

	t.Run("ownership change", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		// NOTE: You cannot use fakegithub.GitTFSRepoID for this test because
		// spokes refuses to diff due to a memory limit error due to the
		// force push done by the "incremental index on push" test.
		repo := fakeGitHub.RepositoryForID(fakegithub.GoGitRepoID)

		// NOTE: After backfilling we can query by the original owner login
		query := &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d owner_id:%d "git repository fixtures"`, repo.ID, repo.OwnerID),
			EpochId: uint32(epochID),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		}

		queryClient := helpers.BlackbirdQueryClient(t)
		response, err := queryClient.Query(ctx, query)
		require.NoError(t, err)
		require.Equal(t, 1, len(response.Documents), debugDocuments(t, response.Documents))
		require.Empty(t, response.QueryErrors)
		require.Equal(t, fakegithub.GoGitOwnerID, response.Documents[0].Locations[0].OwnerId)

		const (
			newOwnerID    = uint32(123)
			newOwnerLogin = "new-owner"
		)

		repo.OwnerID = newOwnerID
		repo.OwnerLogin = fakegithub.RepoOwnerLoginWithTenant(newOwnerLogin)
		fakeGitHub.UpdateRepository(repo.ID, repo)

		ctx := context.Background()
		client := helpers.BlackbirdAdminClient(t)
		_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoNwo: repoNWOWithTenant(newOwnerLogin, repo.Name)})
		require.NoError(t, err)

		latestOffset = waitForIngestToFinish(t, corpus, repo.ID, epochID, latestOffset)
		waitForFullCompaction(t, corpus, epochID, latestOffset, fakeGitHub)

		// NOTE: This query (without owner ID restriction) should return results, and the owner ID should be the new one
		query = &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d "git repository fixtures"`, repo.ID),
			EpochId: uint32(epochID),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		}

		response, err = queryClient.Query(ctx, query)
		require.NoError(t, err)
		require.Equal(t, 1, len(response.Documents), debugDocuments(t, response.Documents))
		require.Empty(t, response.QueryErrors)
		require.Equal(t, newOwnerID, response.Documents[0].Locations[0].OwnerId)

		// NOTE: This query (with the new owner ID) should work after full compaction
		query = &queryPb.QueryRequest{
			Query:   fmt.Sprintf(`repo_id:%d owner_id:%d "git repository fixtures"`, repo.ID, newOwnerID),
			EpochId: uint32(epochID),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		}

		response, err = queryClient.Query(ctx, query)
		require.NoError(t, err)

		require.Equal(t, 1, len(response.Documents), debugDocuments(t, response.Documents))
		require.Empty(t, response.QueryErrors)
		require.Equal(t, newOwnerID, response.Documents[0].Locations[0].OwnerId)
	})

	t.Run("incremental index of deleted repo", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		repo := fakeGitHub.RepositoryForID(fakegithub.GitHubGritRepoID)
		// NOTE: Use the index's current serving offset, not the repos's, because the repo is probably not the most recently ingested one.
		priorServingOffset := minServingOffset(t, epochID)

		// Global query for a result that exists in a single repo, verify expected results are returned.
		query(t, `"Filenames can have weird characters"`, epochID, 1)

		// Delete the repo.
		fakeGitHub.DeleteRepository(repo.ID)
		// Add the repo back for subsequent tests.
		defer func() { fakeGitHub.AddRepository(repo) }()

		// Tell blackbird-admin to index the deleted repo by ID (this skips checking the internal GH API).
		client := helpers.BlackbirdAdminClient(t)
		_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoId: uint32(repo.ID)})
		require.NoError(t, err)

		// Allow the index and compaction to finish.
		waitForServingOffsetToExceed(t, epochID, priorServingOffset)
		waitForFullCompaction(t, corpus, epochID, latestOffset, fakeGitHub)

		// Query for the same result, verify no results are returned.
		query(t, `"Filenames can have weird characters"`, epochID, 0)

		db := schemas.DB("localhost-test", "")
		var deletedTs sql.NullTime
		err := db.Get(&deletedTs, "SELECT deleted_at FROM blackbird_repositories WHERE id=?", repo.ID)
		require.NoError(t, err)
		require.True(t, deletedTs.Valid)
	})

	t.Run("change cache cluster", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		ctx := context.Background()
		// choose a different corpus than the one we've been working with so the
		// cache cluster hasn't been set yet and we don't mess with other tests
		corpus := helpers.OtherCorpus(t, corpus)
		client := helpers.BlackbirdAdminClient(t)

		res, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
		require.NoError(t, err)

		var cacheCluster string
		for _, status := range res.Statuses {
			if status.CorpusName != corpus.String() {
				continue
			}

			cacheCluster = status.CacheCluster
		}

		var newCacheCluster string
		for _, cluster := range routing.CacheClusterNames {
			if cluster != cacheCluster {
				newCacheCluster = cluster
				break
			}
		}
		require.NotEmpty(t, newCacheCluster, "could not find a different cache cluster")

		_, err = client.SetCorpusCacheCluster(ctx, &adminPb.SetCorpusCacheClusterRequest{Corpus: corpus.String(), CacheCluster: newCacheCluster})
		require.NoError(t, err)

		start := time.Now()
		require.Eventually(
			t,
			func() bool {
				res, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
				require.NoError(t, err, "getting corpus status shouldn't fail")
				for _, status := range res.Statuses {
					if status.CorpusName != corpus.String() {
						continue
					}

					if status.CacheCluster == newCacheCluster {
						t.Logf("cache cluster updated from %q to %q after %s", cacheCluster, newCacheCluster, time.Since(start))
						return true
					}
				}

				return false
			},
			1*time.Minute,
			100*time.Millisecond,
			"cache cluster not eventually reflected in DSA state",
		)
	})

	// !!!
	//
	// NOTE: The following tests check if any preceeding tests failed before running.
	//
	// They do this because they cause services to restart, losing log entries that would
	// be useful for debugging earlier failures.
	//
	// !!!

	preceedingTestFailed := t.Failed()
	// NOTE: This test takes some time to run (order of about a minute)
	t.Run("pin", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		if preceedingTestFailed {
			t.Skip("Skipping the pin test due to an earlier test failure to help preserve the logs for debugging.")
		}

		ctx := context.Background()
		client := helpers.BlackbirdAdminClient(t)

		// Record the current serving offset and timestamp
		originalServingOffset, originalServingTs := getServingOffsetAndTs(t, corpus)
		fmt.Printf("\t[pin] current serving_ts: %v, serving_offset: %v\n", originalServingTs, originalServingOffset)
		fmt.Printf("\t[pin] will pin to serving_ts: %v\n", originalServingTs)

		// Ingest an incremental change and wait for the serving offset to move forward
		repo := fakeGitHub.RepositoryForID(fakegithub.GitTFSRepoID)
		repo.NumStars += 1
		fakeGitHub.UpdateRepository(fakegithub.GitTFSRepoID, repo)

		// Force the next documents to have a LogAppendTime in the future
		time.Sleep(1 * time.Second)

		// Trigger an incremental index of this repo
		_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{
			RepoNwo: repoNWOWithTenant("git-tfs", "git-tfs.github.com"),
		})
		require.NoError(t, err)

		// NB: Give the mw-ingest service a chance to pick up this incremental
		// change and create an ingest record.
		time.Sleep(2 * time.Second)

		// Wait for ingest to complete
		latestOffset = waitForIngestToFinish(t, corpus, fakegithub.GitTFSRepoID, epochID, latestOffset)
		require.True(t, int64(latestOffset) > originalServingOffset, "waited for ingest to finish, but serving offset didn't increase")

		// Pin
		_, err = client.PinCorpus(ctx, &adminPb.PinCorpusRequest{Corpus: corpus.String(), ServingTs: originalServingTs})
		require.NoError(t, err)
		s, err := waitForClusterToPin(t, client, corpus, originalServingTs)
		require.NoError(t, err)
		require.Equal(t, originalServingTs, s.PinnedServingTs.Value)
		require.False(t, s.Indexing)
		fmt.Printf("\t[pin] successfully pinned to serving_ts: %v, serving_offset: %v\n", utils.TimeFromServingTs(s.ServingTs), s.ServingOffset)

		// Unpin and check that unpinning re-enables indexing and clears the pinnedTs.
		_, err = client.UnpinCorpus(ctx, &adminPb.UnpinCorpusRequest{Corpus: corpus.String()})
		require.NoError(t, err)
		s, err = waitForClusterToUnpin(t, client, corpus, int64(latestOffset))
		require.NoError(t, err)
		require.True(t, s.Indexing)
		fmt.Printf("\t[pin] resumed serving_ts: %v, serving_offset: %v\n", utils.TimeFromServingTs(s.ServingTs), s.ServingOffset)
	})

	preceedingTestFailed = t.Failed()
	t.Run("branch-epoch", func(t *testing.T) {
		if epoch.EpochFeaturesEmbeddings.SupportedBy(epochMode) {
			t.Skip("this does not run in embeddings mode")
		}
		if preceedingTestFailed {
			t.Skip("Skipping the epoch branching test due to an earlier test failure to help preserve the logs for debugging.")
		}

		ctx := context.Background()
		client := helpers.BlackbirdAdminClient(t)

		fmt.Printf("\t[branch-epoch] creating a new branch: %v\n", utils.TimeFromServingTs(branchTs))
		// Create a new branch
		res, err := client.BranchEpoch(ctx, &adminPb.BranchEpochRequest{
			SourceEpoch:  uint32(epochID),
			SourceCorpus: corpus.String(),
			Corpus:       corpus.String(),
			BranchTs:     branchTs,
			Reason:       "integration testing",
			EpochMode:    blackbird.ConvertEpochMode(epochMode),
			NumShards:    numBlackbirdShards,
		})
		require.NoError(t, err)

		epochID = types.EpochID(res.EpochId)
		waitForShardsToServeEpoch(t, epochID)
		priorServingOffset := minServingOffset(t, epochID)
		fmt.Printf("\t[branch-epoch] new branch is serving at offset: %v\n", priorServingOffset)

		fakeGitHub.AddRepository(epochBranchingRepoWithTenant())
		// Trigger an incremental index of a new repo to ensure that incremental ingests work after
		// branching is done.
		_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{
			RepoId: uint32(fakegithub.EpochBranchingRepoID),
		})
		require.NoError(t, err)

		// NB: Give the mw-ingest service a chance to pick up this incremental
		// change and create an ingest record.
		time.Sleep(2 * time.Second)

		// Wait for ingest to complete
		_ = waitForIngestToFinish(t, corpus, fakegithub.EpochBranchingRepoID, epochID, routing.ServingOffset(priorServingOffset))

		// Repos indexed before the branchTS should be present in the index. Run
		// some queries to ensure that's true.
		query(t, "repo_id:1 path:_includes/download_button.html", epochID, 1)
		query(t, "repo_id:1 path:_layouts/default.htm", epochID, 1)
		query(t, "repo_id:1 path:_layouts/markdown.htm", epochID, 1)

		// Query the new repo that we just ingested to ensure the branch can continue
		// indexing new repos.
		query(t, "repo:mbellani/code-search-test path:Cargo.toml", epochID, 1)
	})
}

func getServingOffsetAndTs(t *testing.T, corpus routing.Corpus) (int64, int64) {
	ctx := context.Background()
	client := helpers.BlackbirdAdminClient(t)

	var servingOffset int64
	var servingTs int64
	res, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
	require.NoError(t, err)
	for _, s := range res.Statuses {
		if s.CorpusName == corpus.String() {
			servingOffset = s.ServingOffset
			servingTs = s.ServingTs
			break
		}
	}

	return servingOffset, servingTs
}

// Wait until PinnedServingTs is set and the cluster reports serving `ts`.
func waitForClusterToPin(t *testing.T, client adminPb.AdminAPI, corpus routing.Corpus, ts int64) (*adminPb.CorpusStatus, error) {
	t.Helper()

	ctx := context.Background()
	count := 0
	for {
		res, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
		require.NoError(t, err)
		for _, s := range res.Statuses {
			if s.CorpusName == corpus.String() {
				if s.PinnedServingTs != nil && s.ServingTs <= ts {
					return s, nil
				}
			}
		}
		count++
		if count >= 300 {
			return nil, errors.New("timed out waiting for cluster to pin")
		}
		time.Sleep(1 * time.Second)
	}
}

// Wait until PinnedServingTs is nil and the cluster reports serving at least `offset`.
func waitForClusterToUnpin(t *testing.T, client adminPb.AdminAPI, corpus routing.Corpus, offset int64) (*adminPb.CorpusStatus, error) {
	t.Helper()

	ctx := context.Background()
	count := 0
	for {
		res, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
		require.NoError(t, err)
		for _, s := range res.Statuses {
			if s.CorpusName == corpus.String() {
				if s.PinnedServingTs == nil && s.ServingOffset >= offset {
					return s, nil
				}
			}
		}
		count++
		if count >= 300 {
			return nil, errors.New("timed out waiting for cluster to unpin")
		}
		time.Sleep(1 * time.Second)
	}
}

func query(t *testing.T, q string, epochID types.EpochID, numExpectedResults int, experimentKVs ...string) {
	t.Helper()

	expers := map[string]string{}
	for _, key := range experimentKVs {
		parts := strings.Split(key, "=")
		val := ""
		if len(parts) == 2 {
			val = parts[1]
		}
		if len(parts) > 1 {
			expers[parts[0]] = val
		}
	}
	ctx := context.Background()
	client := helpers.BlackbirdQueryClient(t)
	queryRequest := &queryPb.QueryRequest{
		Query:       q,
		EpochId:     uint32(epochID),
		Experiments: expers,
		Tenant:      fakegithub.Tenant(),
		Actor:       generateActor(hubotUserID, fakegithub.AllAccessToken),
	}
	response, err := client.Query(ctx, queryRequest)
	require.NoError(t, err, "query %q error. ServingStatus: %+v", q, servingStatus(err))
	require.Empty(t, response.QueryErrors, "query %q returned unexpected errors.\n\nResponse:\n\n%s", q, debugResponse(t, response))

	if tenantMode {
		for _, doc := range response.Documents {
			for _, loc := range doc.Locations {
				require.NotContains(t, loc.RepoNwo, fakegithub.Tenant().Shortcode, "query %q returned an NWO with a short code.\n\nResponse:\n\n%s", q, debugResponse(t, response))
			}
		}
	}

	// NOTE: Using assert here allows queries to continue running if the
	// number of results isn't correct. Rather than failing fast, other
	// tests may give us more data about the state of the index.
	assert.Equal(
		t,
		numExpectedResults,
		len(response.Documents),
		"query %q returned unexpected number of documents: %s\n\nResponse:\n\n%s",
		q,
		debugDocuments(t, response.Documents),
		debugResponse(t, response),
	)
}

// NB: New Rust-based semantic query mw service.
func semanticQuery(t *testing.T, prompt, scopingQuery string, epochID types.EpochID, numExpectedResults int) {
	t.Helper()

	ctx := context.Background()
	// TODO: Allow specifying tenant in the header
	ctx = semantic.WithActorHeaders(ctx, hubotUserID, fakegithub.AllAccessToken, "127.0.0.1", "session-id")
	ctx = semantic.WithCopilotLicenseHeaders(ctx, "test", false)

	client := helpers.BlackbirdSemanticQueryClient(t)
	queryRequest := &semanticpb.QueryRequest{
		Prompt:            prompt,
		ScopingQuery:      scopingQuery,
		IncludeEmbeddings: true,
		Limit:             100,
		Experiments:       map[string]string{"epoch_id": fmt.Sprintf("%d", epochID)}, // NB: Force querying a specific epoch
	}
	response, err := client.Query(ctx, queryRequest)
	require.NoError(t, err, "prompt query %q (%s) error. ServingStatus: %+v", prompt, scopingQuery, servingStatus(err))

	// TODO: Support proxima (tenant mode) in the Rust middleware service
	// if tenantMode {
	// 	for _, res := range response.Results {
	// 		require.NotContains(t, loc.RepoNwo, fakegithub.Tenant().Shortcode, "query %q returned an NWO with a short code.\n\nResponse:\n\n%s", q, debugResponse(t, response))
	// 	}
	// }

	// NOTE: Using assert here allows queries to continue running if the
	// number of results isn't correct. Rather than failing fast, other
	// tests may give us more data about the state of the index.
	assert.Equal(
		t,
		numExpectedResults,
		len(response.Results),
		"prompt query %q (%s) returned unexpected number of results: %v\n\n",
		prompt,
		scopingQuery,
		response.Results,
	)
}

func legacyQuery(t *testing.T, q string, numExpectedResults int) {
	t.Helper()

	ctx := context.Background()
	client := helpers.BlackbirdQueryClient(t)
	response, err := client.LegacyQuery(ctx, &queryPb.LegacyQueryRequest{
		Query:          q,
		PageNumber:     0,
		ResultsPerPage: 100,
		Actor:          generateActor(123, fakegithub.AllAccessToken),
	})
	require.NoError(t, err)
	require.Empty(t, response.QueryErrors)

	// NOTE: Using assert to allow queries to continue if this fails.
	assert.Equal(t, numExpectedResults, len(response.Results), "query %q returned unexpected number of results: %s", q, debugResults(t, response.Results))
}

// Convert response to JSON for debugging of failed queries.
func debugResponse(t *testing.T, res *queryPb.QueryResponse) string {
	t.Helper()

	opts := protojson.MarshalOptions{
		Multiline:       true,
		Indent:          "  ",
		UseProtoNames:   true,
		UseEnumNumbers:  false,
		EmitUnpopulated: true,
	}
	return opts.Format(res)
}

// Do an empty backfill to bootstrap the system
func coldstartBackfill(t *testing.T, corpus routing.Corpus, github *fakegithub.FakeGitHubAPIHttpClient) (types.EpochID, routing.ServingOffset) {
	t.Helper()

	fmt.Printf("### => Doing an empty backfill for corpus=%s\n", corpus.String())

	ctx := context.Background()
	client := helpers.BlackbirdAdminClient(t)

	r, err := client.BackfillCorpus(
		ctx,
		&adminPb.BackfillCorpusRequest{
			Corpus:    corpus.String(),
			Reason:    t.Name(),
			Bootstrap: true,
			EpochMode: blackbird.ConvertEpochMode(epochMode),
			NumShards: numBlackbirdShards,
		})
	require.NoError(t, err)
	epochID := types.EpochID(r.EpochId)

	cacheCluster := cacheClusterForCorpus(t, ctx, client, corpus)
	_, err = client.ChangeEpoch(ctx, &adminPb.ChangeEpochRequest{Cluster: cacheCluster, EpochId: r.EpochId, EpochMode: blackbird.ConvertEpochMode(epochMode), NumShards: numBlackbirdShards})
	require.NoError(t, err)

	waitForCacheClusterToServeEpoch(t, ctx, epochID, routing.ServingOffset(0)) // ServingOffset of 0 is OK to publish messages

	// blackbird-ingest restarts when we change the epoch. Wait for it to come
	// back up before publishing onboarding messages.
	waitForIngestReady(t)

	// Trigger an incremental index of a few repos to get started
	for _, repo := range fakegithub.ReposForTestWithTenant() {
		_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoId: uint32(repo.ID)})
		require.NoError(t, err, "error indexing repo %q", repo.ID)
	}

	latestOffset := waitForAllReposToIngest(t, corpus, epochID)
	toggleServingCorpus(t, ctx, client, corpus)
	waitForFullCompaction(t, corpus, epochID, latestOffset, github)
	return epochID, latestOffset
}

func mstBackfill(t *testing.T, ctx context.Context, corpus routing.Corpus, mstEpochID types.EpochID, latestOffset routing.ServingOffset, github *fakegithub.FakeGitHubAPIHttpClient) (types.EpochID, routing.ServingOffset) {
	t.Helper()

	fmt.Printf("### => doing an MST driven backfill for corpus=%s using epoch=%d\n", corpus.String(), mstEpochID)

	// NOTE: This repository is published as an onboarding message in `mstBackfill`
	insertRepoToDB(t, deletedRepo)

	client := helpers.BlackbirdAdminClient(t)

	// put another corpus in serving state so backfill will work
	toggleServingCorpus(t, ctx, client, routing.GetOtherCorpora(corpus, routing.Dotcom)[0])

	// HACK: Go to epoch 0 and then to 1 to trick the cache server into downloading
	cacheCluster := cacheClusterForCorpus(t, ctx, client, corpus)
	_, err := client.ChangeEpoch(ctx, &adminPb.ChangeEpochRequest{EpochId: 0, Cluster: cacheCluster, EpochMode: blackbird.ConvertEpochMode(epochMode), NumShards: numBlackbirdShards})
	require.NoError(t, err)
	waitForCacheClusterToServeEpoch(t, ctx, 0, routing.ServingOffset(0)) // ServingOffset of 0 is OK to publish messages
	_, err = client.ChangeEpoch(ctx, &adminPb.ChangeEpochRequest{EpochId: uint32(mstEpochID), Cluster: cacheCluster, EpochMode: blackbird.ConvertEpochMode(epochMode), NumShards: numBlackbirdShards})
	require.NoError(t, err)
	waitForCacheClusterToServeEpoch(t, ctx, mstEpochID, latestOffset) // wait for it to serve the latest offset so that we get all repos in the mst.

	// Perform an MST backfill
	r, err := client.BackfillCorpus(ctx, &adminPb.BackfillCorpusRequest{Corpus: corpus.String(), EpochId: uint32(mstEpochID), EpochMode: blackbird.ConvertEpochMode(epochMode), NumShards: numBlackbirdShards, Reason: t.Name()})
	require.NoError(t, err)
	epochID := types.EpochID(r.EpochId)
	fmt.Printf("\t[epoch=%d] published %d repositories for indexing\n", r.EpochId, r.NumRepositories)
	// TODO: Add number of repositories to MST stats so we can print it here and in chatops
	//require.Equal(t, uint32(len(reposForTestWithfakegithub.Tenant())), r.NumRepositories, "MST incomplete")

	offset := waitForAllReposToIngest(t, corpus, epochID)

	// Publish an onboarding message for the deleted repo since deleted repos are no longer published by the backfill code
	// See: https://github.com/github/blackbird-mw/pull/2339
	_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoId: uint32(deletedRepo.ID)})
	require.NoError(t, err)
	fmt.Printf("\t[epoch=%d] onboarded the deleted repo\n", r.EpochId)

	toggleServingCorpus(t, ctx, client, corpus)
	waitForFullCompaction(t, corpus, epochID, offset, github)

	return epochID, offset
}

func waitForAllReposToIngest(t *testing.T, corpus routing.Corpus, epochID types.EpochID) routing.ServingOffset {
	t.Helper()
	fmt.Printf("#### => waitForAllReposToIngest\n")

	// Because repos can ingest out of order, we need to find the max offset across all repos we
	// expect to be in the cluster and wait for that offset to serve.
	var maxOffset routing.ServingOffset
	var count int
	start := time.Now()
	for _, r := range fakegithub.ReposForTestWithTenant() {
		var attempts int
		for {
			if attempts > 120 {
				require.Fail(t, "timeout", "timed out looking for serving offsets of repo_id=%d (tried %d times in %s)", r.ID, attempts, time.Since(start))
			}
			attempts++

			offset := repoServingOffset(t, corpus, r.ID, epochID)
			if offset == 0 {
				time.Sleep(1 * time.Second) // Give the mw a chance to pick up these repos
				continue
			}
			if offset > maxOffset {
				maxOffset = offset
			}
			break
		}
		count++
	}
	fmt.Printf("\t[epoch=%d] %d repositories indexed, last serving_offset=%d\n", epochID, count, maxOffset)
	return waitForServingOffsetToExceed(t, epochID, maxOffset)
}

func cacheClusterForCorpus(t *testing.T, ctx context.Context, client adminPb.AdminAPI, corpus routing.Corpus) string {
	res, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
	require.NoError(t, err)

	for _, status := range res.Statuses {
		if routing.Corpus(status.CorpusId) != corpus {
			continue
		}

		return status.CacheCluster
	}

	require.Fail(t, "impossible cache cluster status", "no statuses matched corpus %d", corpus)
	return ""
}

func toggleServingCorpus(t *testing.T, ctx context.Context, client adminPb.AdminAPI, corpus routing.Corpus) {
	t.Helper()
	fmt.Printf("#### => toggleServingCorpus\n")

	_, err := client.SetServingCorpus(ctx, &adminPb.SetServingCorpusRequest{Corpus: corpus.String()})
	require.NoError(t, err)

	// Wait for DSA state to converge to SERVING
	count := 0
	start := time.Now()
	for {
		resp, err := client.GetCorpusStatus(ctx, &adminPb.GetCorpusStatusRequest{})
		require.NoError(t, err)
		for _, status := range resp.Statuses {
			if status.GetCorpusName() == corpus.String() && status.Serving {
				t.Logf("requested corpus/cluster: %s/%s is now serving", status.CorpusName, status.ClusterName)
				return
			}
		}

		count++
		if count == 30 {
			json, err := protojson.Marshal(resp)
			require.NoError(t, err)
			if err == nil {
				t.Logf("final response:%s", string(json))
			}

			require.Fail(t, "timeout", "timed out waiting for %s corpus to be served (tried %d times in %s)", corpus, count, time.Since(start))
			return
		}
		time.Sleep(1 * time.Second)
	}
}

// Wait for the cache cluster to report it is serving the epoch and at least
// minOffset.
//
// A cache server is ready to PUBLISH documents when it is serving the epoch.
//
// A cache server is ready to generate an MST when it is serving the epoch AND
// has minOffset > 0.
//
// NOTE: epoch ID 0 has a special case where it doesn't require any shards to be
// serving, because epoch 0 doesn't really exist. We switch to epoch 0 and then
// back to another epoch to "trick" the cache server into downloading shards
// from the real epoch.
func waitForCacheClusterToServeEpoch(t *testing.T, ctx context.Context, epochID types.EpochID, minOffset routing.ServingOffset) {
	t.Helper()
	fmt.Printf("#### => waitForCacheClusterToServeEpoch (epoch=%d, min_offset=%d)\n", epochID, minOffset)

	// NOTE: numShards matches the number of Kafka partitions configured in docker-compose.yml
	const numShards = 2

	start := time.Now()
	client := helpers.CacheClusterServingAPI(t)
	count := 0
	for {
		count++
		servingShards := make(map[uint32]bool)
		epochIDs := make(map[types.EpochID]bool)

		status, err := client.Status(ctx, &servingpb.StatusRequest{})
		require.NoError(t, err)

		// HACK: If you didn't ask for special epoch 0 and the host has epoch 0, try again later
		if status.Status.EpochId == 0 && epochID != 0 {
			time.Sleep(100 * time.Millisecond)
			continue
		}

		epochIDs[types.EpochID(status.Status.EpochId)] = true

		for _, s := range status.Status.Shards {
			if routing.ServingOffset(s.ServingOffset) >= minOffset {
				servingShards[s.Id] = true
			}
		}

		shardIDs := []string{}
		for shardID := range servingShards {
			shardIDs = append(shardIDs, strconv.FormatUint(uint64(shardID), 10))
		}

		t.Logf("cache client now serving epoch %d and shards %+v", status.Status.EpochId, shardIDs)

		if len(epochIDs) == 1 && epochIDs[epochID] && epochID == 0 && len(servingShards) == 0 {
			fmt.Printf("\tspecial case: cache cluster is now serving epoch %d with no shards (tried %d times in %s)\n", epochID, count, time.Since(start))
			break
		}

		if len(servingShards) == numShards && len(epochIDs) == 1 && epochIDs[epochID] {
			fmt.Printf("\tcache cluster is now serving epoch %d (tried %d times in %s)\n", epochID, count, time.Since(start))
			break
		}

		const maxDuration = 5 * time.Minute
		if time.Since(start) > maxDuration {
			require.Fail(
				t,
				"timeout",
				"timeout waiting for cache cluster to serve epoch %d. epochs: %+v, servingShards:%+v, expectedShards:%d (tried %d times for %s)",
				epochID,
				epochIDs,
				servingShards,
				numShards,
				count,
				time.Since(start),
			)

		}
		time.Sleep(1 * time.Second)
	}
}

// waitForIngestToFinish polls blackbird-server until the epoch is available and
// the repoID's most recent tree entry's serving offset is available.
func waitForIngestToFinish(t *testing.T, corpus routing.Corpus, repoID types.RepoID, epochID types.EpochID, priorServingOffset routing.ServingOffset) routing.ServingOffset {
	t.Helper()

	waitForShardsToServeEpoch(t, epochID)

	fmt.Printf("\t[epoch=%d] waiting for repo_id=%d to exceed a serving_offset of %d\n", epochID, repoID, priorServingOffset)
	count := 0
	repoOffset := routing.ServingOffset(0)
	for {
		repoOffset = repoServingOffset(t, corpus, repoID, epochID)
		if repoOffset > priorServingOffset {
			fmt.Printf("\t[epoch=%d] ingest of repo_id=%d reached serving_offset=%d (> target offset %d)\n", epochID, repoID, repoOffset, priorServingOffset)
			break
		}

		count++
		if count > 60 {
			require.Fail(t, "timeout", "[epoch=%d] timeout waiting for repo_id=%d (serving_offset=%d) to exceed a serving_offset of %d", epochID, repoID, repoOffset, priorServingOffset)
		}
		time.Sleep(1 * time.Second)
	}

	return waitForServingOffsetToExceed(t, epochID, repoOffset)
}

// Return the serving offset of the latest ACTIVE snapshot entry for repo in epoch, or 0.
func repoServingOffset(t *testing.T, corpus routing.Corpus, repoID types.RepoID, epochID types.EpochID) routing.ServingOffset {
	t.Helper()

	ctx := context.Background()
	res, err := repoStatusRPC(t, ctx, corpus, repoID)
	if err != nil {
		fmt.Printf("\t[epoch=%d] error searching snapshot entry for repo ID %d: %s\n", epochID, repoID, err.Error())
		return routing.ServingOffset(0)
	}

	var maxServingOffset int64
	for _, ingest := range res.IndexerIngests {
		if ingest.Corpus != corpus.String() {
			continue
		}

		// We checked this before, so it should not be possible: fail the test
		if types.EpochID(ingest.EpochId) != epochID {
			require.Fail(
				t,
				"impossible epoch ID for ingest",
				"epoch ID in ingest (%d) does not match test epoch ID (%d) for corpus %s",
				ingest.EpochId,
				epochID,
				ingest.Corpus,
			)
			return routing.ServingOffset(0)
		}

		for _, entry := range ingest.SnapshotEntries {
			if entry.EntryState == "SNAPSHOT_ENTRY_STATE_ACTIVE" {
				if entry.ServingOffset > maxServingOffset {
					maxServingOffset = entry.ServingOffset
				}
			}
		}
	}

	if maxServingOffset == 0 {
		fmt.Printf("\t[epoch=%d] could not find snapshot entry for repo ID %d\n", epochID, repoID)
	} else {
		minServingOffset := minServingOffset(t, epochID)
		fmt.Printf("\t[epoch=%d] found snapshot entry for repo ID %d, serving_offset=%d. min_serving_offset=%d\n", epochID, repoID, maxServingOffset, minServingOffset)
	}
	return routing.ServingOffset(maxServingOffset)
}

func repoStatusRPC(t *testing.T, ctx context.Context, corpus routing.Corpus, repoID types.RepoID) (*adminPb.GetRepoStatusResponse, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()

	client := helpers.BlackbirdAdminClient(t)
	return client.GetRepoStatus(ctx, &adminPb.GetRepoStatusRequest{
		RepoId: uint32(repoID),
		Corpus: corpus.String(),
	})
}

// wait for blackbird-server to load the new epoch by making query with this epoch ID.
func waitForShardsToServeEpoch(t *testing.T, epochID types.EpochID) {
	fmt.Printf("\t[epoch=%d] waiting for shards to serve epoch\n", epochID)

	ctx := context.Background()
	client := helpers.BlackbirdQueryClient(t)
	count := 0
	for {
		res, err := client.Query(ctx, &queryPb.QueryRequest{
			Query:   "helper=waitForShardsToServeEpoch",
			EpochId: uint32(epochID),
			Actor:   generateActor(123, fakegithub.AllAccessToken),
		})
		if err == nil {
			allEpochsMatch := true
			for _, shard := range res.Metadata.Shards {
				if shard.Status.EpochId != uint32(epochID) {
					fmt.Printf("\t[epoch=%d] shard %s is still serving epoch=%d\n", epochID, shard.Hostname, shard.Status.EpochId)
					allEpochsMatch = false
				}
			}

			if allEpochsMatch {
				fmt.Printf("\t[epoch=%d] all shards are serving this epoch now\n", epochID)
				break
			}

		} else {
			fmt.Printf("\t[epoch=%d] %s\n", epochID, err.Error())
		}

		count++
		if count > 120 {
			require.Fail(t, "timeout", "timeout waiting for blackbird-server to serve epoch %d", epochID)
		}
		time.Sleep(1 * time.Second)
	}
}

// TODO: Rename this method when switching to snapshot queries entirely
func waitForServingOffsetToExceed(t *testing.T, epochID types.EpochID, offset routing.ServingOffset) routing.ServingOffset {
	waitForShardsToServeEpoch(t, epochID)

	fmt.Printf("\t[epoch=%d] waiting for serving_offset of %d\n", epochID, offset)
	attempts := 0
	for {
		servingOffset := minServingOffset(t, epochID)
		if servingOffset > offset {
			fmt.Printf("\t[epoch=%d] minimum serving_offset=%d exceeded target offset %d\n", epochID, servingOffset, offset)
			return servingOffset
		}

		attempts++
		if attempts > 60 {
			require.Fail(t, "timeout", "timeout waiting for epoch %d shard serving_offset=%d to exceed target offset %d", epochID, servingOffset, offset)
		}
		time.Sleep(1 * time.Second)
	}
}

func minServingOffset(t *testing.T, epochID types.EpochID) routing.ServingOffset {
	client := helpers.BlackbirdQueryClient(t)
	res, err := client.Query(context.Background(), &queryPb.QueryRequest{
		Query:   "helper=minServingOffset",
		EpochId: uint32(epochID),
		Actor:   generateActor(123, fakegithub.AllAccessToken),
	})
	if err != nil {
		fmt.Printf("\t[epoch=%d] failed to get min serving offset: %v\n", epochID, err)
		return routing.ServingOffset(0)
	}
	return routing.ServingOffset(res.ServingOffsetQueried)
}

func waitForSemanticServingOffsetToExceed(t *testing.T, epochID types.EpochID, offset routing.ServingOffset) routing.ServingOffset {
	// TODO: This isn't necessary right now b/c the Go mw code does this wait, but when we switch to 100% Rust middleware,
	// we'll need implement this.
	// waitForShardsToServeEpoch(t, epochID)

	fmt.Printf("\t[epoch=%d] waiting for serving_offset of %d\n", epochID, offset)
	attempts := 0
	for {
		servingOffset := minSemanticServingOffset(t, epochID)
		if servingOffset > offset {
			fmt.Printf("\t[epoch=%d] minimum serving_offset=%d exceeded target offset %d\n", epochID, servingOffset, offset)
			return servingOffset
		}

		attempts++
		if attempts > 60 {
			require.Fail(t, "timeout", "timeout waiting for epoch %d shard serving_offset=%d to exceed target offset %d", epochID, servingOffset, offset)
		}
		time.Sleep(1 * time.Second)
	}
}

func minSemanticServingOffset(t *testing.T, epochID types.EpochID) routing.ServingOffset {
	t.Helper()

	client := helpers.BlackbirdSemanticQueryClient(t)
	ctx := context.Background()
	ctx = semantic.WithActorHeaders(ctx, hubotUserID, fakegithub.AllAccessToken, "127.0.0.1", "session-id")
	ctx = semantic.WithCopilotLicenseHeaders(ctx, "test", false)
	res, err := client.Query(ctx, &semanticpb.QueryRequest{
		Prompt:            "helper=minServingOffset",
		ScopingQuery:      "repo:go-git/go-git-fixtures", // NB: ScopingQuery required and repo is the only supported qualifier right now.
		IncludeEmbeddings: false,
		Limit:             100,
		Experiments:       map[string]string{"epoch_id": fmt.Sprintf("%d", epochID)}, // NB: Force querying a specific epoch
	})

	if err != nil {
		fmt.Printf("\t[epoch=%d] failed to get min serving offset: %v\n", epochID, err)
		var twErr twirp.Error
		if errors.As(err, &twErr) {
			fmt.Printf("\t[epoch=%d] twirp error: %v, msg: %v, body: %v\n", epochID, twErr, twErr.Msg(), twErr.MetaMap())
		}
		return routing.ServingOffset(0)
	}
	return routing.ServingOffset(res.ServingOffsetQueried)
}

// Wait for a full compaction by triggering it, and then a flush a repo change
// to move offsets forward.
//
// NOTE: compacting doesn't increase the serving offset, because the offset of
// the compaction message is not included in the compacted subtree.
func waitForFullCompaction(t *testing.T, corpus routing.Corpus, epochID types.EpochID, latestOffset routing.ServingOffset, github *fakegithub.FakeGitHubAPIHttpClient) {
	t.Helper()
	fmt.Printf("#### => waitForFullCompaction\n")

	fmt.Printf("\t[epoch=%d] triggering full compaction\n", epochID)
	ctx := context.Background()
	client := helpers.BlackbirdAdminClient(t)
	res, err := client.CompactCorpus(ctx, &adminPb.CompactCorpusRequest{Corpus: corpus.String(), CompactionType: adminPb.CompactionType_COMPACTION_TYPE_FULL})
	require.NoError(t, err)
	require.Greater(t, res.ServingOffset, uint64(0), "unexpected serving offset returned from CompactCorpus")

	// Publish another snapshot update which includes a snapshot, and wait for it to be servable.
	repo := github.RepositoryForID(fakegithub.FlushRepoID)
	repo.Archived = !repo.Archived
	github.UpdateRepository(fakegithub.FlushRepoID, repo)
	_, err = client.IndexRepo(ctx, &adminPb.IndexRepoRequest{RepoNwo: repo.NWO()})
	require.NoError(t, err)
	// NB: We don't want the rest of the tests to wait around on the very latest offset (which happened after the full compaction).
	o := waitForServingOffsetToExceed(t, epochID, latestOffset)
	fmt.Printf("\t[epoch=%d] full compaction complete at offset=%d (latest offset=%d not included in the full compaction)\n", epochID, latestOffset, o)
}

// waitForIngestReady waits for a fixed period of time to give the indexer time
// to come back up after restarting.
//
// TODO: Expose a way for the indexer to report ready, or consume onboarding
// messages from the beginning of the topic instead of the end.
func waitForIngestReady(t *testing.T) {
	t.Helper()
	fmt.Printf("#### => waitForIngestReady\n")
	time.Sleep(10 * time.Second) // On CI, this takes about 5 seconds, so I've doubled it.
}

func amendHeadCommit(t *testing.T, file, content string) {
	const repoDir = "repositories/1/nw/16/79/09/6/6.git"

	pristineDir, err := os.MkdirTemp("", "javaTest")
	fmt.Println(pristineDir)
	require.NoError(t, err)

	workDir, err := os.MkdirTemp("", "javaTest")
	fmt.Println(workDir)
	require.NoError(t, err)

	cmd := exec.Command("git", "clone", "../../../deps/spokes-proto/"+repoDir, pristineDir)
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, string(out))
	fmt.Println(string(out))

	cmd = exec.Command("git", "clone", "../../../deps/spokes-proto/"+repoDir, workDir)
	out, err = cmd.CombinedOutput()
	require.NoError(t, err, string(out))
	fmt.Println(string(out))

	sha := runCommand(t, pristineDir, "git", "log", "-n", "1", "--format=format:%H")
	fmt.Printf("Will reset to %s in test cleanup\n", sha)

	f, err := os.Create(workDir + "/" + file)
	require.NoError(t, err)
	_, err = f.WriteString(content)
	require.NoError(t, err)
	_, err = f.WriteString(fmt.Sprintf("%v\n", time.Now()))
	require.NoError(t, err)
	err = f.Close()
	require.NoError(t, err)

	runCommand(t, workDir, "git", "config", "user.email", `test@github.com`)
	runCommand(t, workDir, "git", "config", "user.name", `Integration Test`)

	runCommand(t, workDir, "git", "add", ".")
	runCommand(t, workDir, "git", "commit", "--amend", "-m", "amend commit")
	runCommand(t, workDir, "git", "push", "--force")

	runCommand(t, "../../../deps/spokes-proto/"+repoDir, "git", "reflog", "expire", "--expire=now", "--all")
	runCommand(t, "../../../deps/spokes-proto/"+repoDir, "git", "gc", "--prune=now")

	t.Cleanup(func() {
		runCommand(t, pristineDir, "git", "push", "-f")

		// remove this temporary git repo
		os.RemoveAll(pristineDir)
		os.RemoveAll(workDir)
		fmt.Printf("Reset to %s and deleted local clones \n", sha)
	})
}

// Writes a file, commits, and pushes. Only works for repoID = 1.
func commitAndPush(t *testing.T, file, content string) {
	const repoDir = "repositories/c/nw/c4/ca/42/1/1.git"

	dir, err := os.MkdirTemp("", "git-tfs")
	fmt.Println(dir)
	require.NoError(t, err)

	cmd := exec.Command("git", "clone", "../../../deps/spokes-proto/"+repoDir, dir)
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, string(out))
	fmt.Println(string(out))

	sha := runCommand(t, dir, "git", "log", "-n", "1", "--format=format:%H")
	fmt.Printf("Will reset to %s in test cleanup\n", sha)

	f, err := os.Create(dir + "/" + file)
	require.NoError(t, err)
	_, err = f.WriteString(content)
	require.NoError(t, err)
	_, err = f.WriteString(fmt.Sprintf("%v\n", time.Now()))
	require.NoError(t, err)
	err = f.Close()
	require.NoError(t, err)

	runCommand(t, dir, "git", "add", "-A", ".")
	runCommand(t, dir, "git", "config", "user.email", `test@github.com`)
	runCommand(t, dir, "git", "config", "user.name", `Integration Test`)
	runCommand(t, dir, "git", "commit", "-m", `"Test"`)
	runCommand(t, dir, "git", "push")
	runCommand(t, "../../../deps/spokes-proto/"+repoDir, "git", "gc", "--aggressive", "--prune=0")

	t.Cleanup(func() {
		runCommand(t, dir, "git", "reset", "--hard", sha)
		runCommand(t, dir, "git", "push", "-f")
		runCommand(t, "../../../deps/spokes-proto/"+repoDir, "git", "gc", "--aggressive", "--prune=0")

		// remove this temporary git repo
		os.RemoveAll(dir)
		fmt.Printf("Reset to %s and deleted local clone \n", sha)
	})
}

func runCommand(t *testing.T, dir, name string, args ...string) string {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	require.NoError(t, err, string(out))
	output := string(out)
	fmt.Println(output)
	return output
}

func debugDocuments(t *testing.T, docs []*queryPb.GitDocumentMatch) string {
	t.Helper()

	strs := []string{}
	for _, doc := range docs {
		sha := hex.EncodeToString(doc.GetBlobSha())

		locations := []string{}
		for _, loc := range doc.GetLocations() {
			locations = append(locations, fmt.Sprintf("<RepoID: %d, Public: %t, Path: %s>", loc.RepoId, loc.IsRepoPublic, loc.Path))
		}

		strs = append(strs, fmt.Sprintf("<GitDocumentMatch<OID: %s, Locations: %s>>", sha, strings.Join(locations, ", ")))
	}

	return strings.Join(strs, ", ")
}

func debugResults(t *testing.T, results []*queryPb.SearchResult) string {
	t.Helper()

	strs := []string{}
	for _, result := range results {
		sha := hex.EncodeToString([]byte(result.GetBlobSha()))
		out := fmt.Sprintf("<SearchResult<OID: %s, RepoID: %d, Path: %s>", sha, result.RepoId, result.Path)

		strs = append(strs, out)
	}

	return strings.Join(strs, ", ")

}

func count(t *testing.T, repoID types.RepoID, epochID types.EpochID, expectedDocs int) {
	t.Helper()

	ctx := context.Background()
	client := helpers.BlackbirdQueryClient(t)
	query := fmt.Sprintf("repo_id:%d", repoID)

	req := &queryPb.QueryRequest{
		Query:         query,
		QueryParser:   queryPb.QueryParser_QUERY_PARSER_BLACKBIRD_V0,
		DocumentLimit: uint32(expectedDocs + 100),
		EpochId:       uint32(epochID),
		Actor:         generateActor(123, fakegithub.AllAccessToken),
	}
	res, err := client.Query(ctx, req)
	require.NoError(t, err, "query %q error: ServingStatus = %+v", query, servingStatus(err))
	require.Empty(t, res.QueryErrors)
	require.Equal(t, expectedDocs, len(res.Documents), "unexpected number of documents for query %q: %s", query, debugDocuments(t, res.Documents))
}

// reposForTestWithTenant returns a slice of test repos that conditionally includes the tenant's shortcode in the repo's owner login value.
func epochBranchingRepoWithTenant() *github.Repository {
	if tenantMode {
		epochBranchingRepo.OwnerLogin = fakegithub.RepoOwnerLoginWithTenant(epochBranchingRepo.OwnerLogin)
	}

	return &epochBranchingRepo
}

func repoNWOWithTenant(owner, name string) string {
	if !tenantMode {
		return fmt.Sprintf("%s/%s", owner, name)
	}

	return fmt.Sprintf("%s/%s", fakegithub.RepoOwnerLoginWithTenant(owner), name)
}

func insertRepoToDB(t *testing.T, repo github.Repository) {
	t.Helper()
	db := schemas.DB("localhost-test", "")
	_ = db.MustExec(
		"REPLACE INTO blackbird_repositories (id, owner_id, owner_login, name, is_public) VALUES (?, ?, ?, ?, ?)",
		repo.ID,
		repo.OwnerID,
		repo.OwnerLogin,
		repo.Name,
		repo.Public,
	)
}

func generateActor(id uint32, token string) *queryPb.Actor {
	return &queryPb.Actor{
		ActorId:            id,
		AccessToken:        token,
		RequestIp:          "127.0.0.1",
		AccessTokenExpires: time.Now().Add(1 * time.Hour).UnixMilli(),
		SessionId:          "fake-session",
	}
}

// Extract ServingStatus from error if there is one. May be nil.
func servingStatus(err error) *servingpb.ServingStatus {
	status, _ := bb.ServingStatus(err)
	return status
}

func parseEpochMode(mode string) epoch.EpochMode {
	switch strings.ToLower(mode) {
	case "lexical":
		return epoch.EpochModeLexical
	case "embeddings":
		return epoch.EpochModeEmbeddings
	case "embeddings_graph":
		return epoch.EpochModeEmbeddingsGraph
	default:
		return epoch.EpochModeHybrid
	}
}

package spokesd

import (
	"context"
	"fmt"
	"net/http"
	"sort"
	"strings"
	"testing"

	"github.com/dnaeon/go-vcr/recorder"
	"github.com/github/spokes-proto/gen/go/v1/commits"
	"github.com/github/spokes-proto/gen/go/v1/references"
	spokesTrees "github.com/github/spokes-proto/gen/go/v1/trees"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

// Many of these test leverage go-vcr. In order to re-generate VCR fixtures
// you'll need to setup an environment for blackbird and spokesd which can be
// done with:
//   script/setup --spokes
//
// You'll also need to comment out SPOKESD_REQUIRE_CLIENT_AUTH_IN_TEST in
// deps/spokes-proto/docker-compose.yml so that spokes doesn't require certs for
// auth.
//
// The default spokesd setup clones git-tfs/git-tfs.github.com and gives it a
// repo_id=1 so that is used as a basic test repo. You can take also local clone
// of the test repo to inspect it:
//   git clone deps/spokes-proto/repositories/c/nw/c4/ca/42/1/1.git tmp/git-tfs

const (
	repoID        = 1
	unknownRepoID = 1001
	spokesdURL    = "http://127.0.0.1:12080" // Matches what's defined in: deps/spokes-proto/docker-compose.yml
)

func Test_ResolveRefDoesNotRetryFatalGetRefErrors(t *testing.T) {
	refsAPI := &mocks.FakeReferencesAPI{}
	refsAPI.GetDefaultBranchReturns(nil, twirp.Malformed.Error("test"))
	client := &GitClient{
		spokesObjectsAPI: &mocks.FakeObjectsAPI{},
		spokesRefsAPI:    refsAPI,
	}

	_, err := client.GetDefaultRef(context.Background(), 1)
	require.Error(t, err)
	require.False(t, IsInvalidRefError(err))
	require.Equal(t, 1, refsAPI.GetDefaultBranchCallCount())
}

// We treat this like a Not Found, which will be skipped. It skips the repo, but
// doesn't ban it. So if it gets fixed, it will be crawled.
func Test_ResolveRef_SymbolicRefErrorReturnsNil(t *testing.T) {
	refsAPI := &mocks.FakeReferencesAPI{}
	refsAPI.GetDefaultBranchReturns(nil, twirp.Internal.Error("git-symbolic-ref: exit status 128"))
	client := &GitClient{
		spokesObjectsAPI: &mocks.FakeObjectsAPI{},
		spokesRefsAPI:    refsAPI,
	}

	refTip, err := client.GetDefaultRef(context.Background(), 1)
	require.NoError(t, err)
	require.Nil(t, refTip)
	require.Equal(t, 1, refsAPI.GetDefaultBranchCallCount())
}

// We treat this like a Not Found, which will be skipped. It skips the repo, but
// doesn't ban it. So when gitmon allows for processing the repo in the future, it will be crawled.
func Test_ResolveRef_TooManyProcessesReturnsError(t *testing.T) {
	refsAPI := &mocks.FakeReferencesAPI{}
	refsAPI.GetDefaultBranchReturns(nil, twirp.ResourceExhausted.Error("gitmon refuses to schedule us: too-many-processes"))
	client := &GitClient{
		spokesObjectsAPI: &mocks.FakeObjectsAPI{},
		spokesRefsAPI:    refsAPI,
	}

	refTip, err := client.GetDefaultRef(context.Background(), 1)
	require.Error(t, err)
	require.True(t, IsGitmonTooManyProcessesError(err))
	require.Nil(t, refTip)
	require.Equal(t, 1, refsAPI.GetDefaultBranchCallCount())
}

func Test_ResolveRefDoesNotRetryFatalResolveObjectErrors(t *testing.T) {
	refsAPI := &mocks.FakeReferencesAPI{}
	refsAPI.GetDefaultBranchReturns(&references.GetDefaultBranchResponse{Reference: spokes.NewReference([]byte("refs/heads/main"))}, nil)
	objectsAPI := &mocks.FakeObjectsAPI{}
	objectsAPI.ResolveObjectReturns(nil, twirp.Malformed.Error("no HEAD ref"))
	client := &GitClient{
		spokesObjectsAPI: objectsAPI,
		spokesRefsAPI:    refsAPI,
	}

	_, err := client.GetDefaultRef(context.Background(), 1)
	require.Error(t, err)
	require.False(t, IsInvalidRefError(err))
	require.Equal(t, 1, objectsAPI.ResolveObjectCallCount())
}

func Test_GetDefaultRefObjectNotFound(t *testing.T) {
	refsAPI := &mocks.FakeReferencesAPI{}
	refsAPI.GetDefaultBranchReturns(&references.GetDefaultBranchResponse{Reference: spokes.NewReference([]byte("refs/heads/main"))}, nil)
	objectsAPI := &mocks.FakeObjectsAPI{}
	objectsAPI.ResolveObjectReturns(nil, twirp.NotFoundError("no HEAD ref"))
	client := &GitClient{
		spokesRefsAPI:    refsAPI,
		spokesObjectsAPI: objectsAPI,
	}

	ref, err := client.GetDefaultRef(context.Background(), 1)
	require.NoError(t, err)
	require.Nil(t, ref)
}

func Test_GetDefaultRefNotFound(t *testing.T) {
	refsAPI := &mocks.FakeReferencesAPI{}
	refsAPI.GetDefaultBranchReturns(nil, twirp.NotFoundError("no default branch"))
	client := &GitClient{
		spokesRefsAPI:    refsAPI,
		spokesObjectsAPI: &mocks.FakeObjectsAPI{},
		opts:             &ClientOpts{Retries: 2},
	}

	ref, err := client.GetDefaultRef(context.Background(), 1)
	require.NoError(t, err)
	require.Nil(t, ref)
}

func Test_GetDefaultRef(t *testing.T) {
	r, err := recorder.New("fixtures/getdefaultref/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	ref, err := client.GetDefaultRef(context.Background(), repoID)
	require.NoError(t, err)
	require.Equal(t, "refs/heads/master", ref.RefName)
	require.Equal(t, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2", ref.CommitOID.String())
}

func Test_Diff(t *testing.T) {
	r, err := recorder.New("fixtures/diff-gemfile/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(
		context.Background(),
		0,
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
	)
	require.NoError(t, err)
	diffEntries := diff[repoID]
	require.Len(t, diffEntries, 2)
	entry := diffEntries[0]
	require.Equal(t, gitaccess.Delete, entry.Change)
	require.Equal(t, "Gemfile.lock", string(entry.Path))
	require.Equal(t, "39e899afbc4a037f2eb5e23de64582a2c28709f9", entry.OID.String())
	entry = diffEntries[1]
	require.Equal(t, gitaccess.Add, entry.Change)
	require.Equal(t, "Gemfile.lock", string(entry.Path))
	require.Equal(t, "765ed12aef9947c93f61ea4a258bc41832fc06ae", entry.OID.String())
}

func Test_DiffSameBaseAndHeadSameRepo(t *testing.T) {
	r, err := recorder.New("fixtures/diff-gemfile/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(
		context.Background(),
		0,
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
	)
	require.NoError(t, err)
	require.Len(t, diff[repoID], 0)
}

func Test_DiffSameBaseAndHeadDifferentRepos(t *testing.T) {
	r, err := recorder.New("fixtures/diff-gemfile/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(
		context.Background(),
		0,
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
		treeish(t, repoID+1, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
	)
	require.NoError(t, err)
	require.Len(t, diff[repoID], 0)
	require.Equal(t, diff[repoID], diff[repoID+1])
}

func Test_DiffBlobsBasic(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/diff-and-getblobs-basic/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(
		ctx,
		0,
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
	)
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.NoError(t, err)

	gotAdd := false
	gotDelete := false
	for _, blob := range blobs {
		require.Len(t, blob.Locations(), 1)
		if blob.BlobLocations[0].Change == gitaccess.Add {
			gotAdd = true
			require.Equal(t, "765ed12aef9947c93f61ea4a258bc41832fc06ae", blob.ObjectID.String())
			require.Equal(t, "Gemfile.lock", blob.BlobLocations[0].Path)
		} else if blob.BlobLocations[0].Change == gitaccess.Delete {
			gotDelete = true
			require.Equal(t, "39e899afbc4a037f2eb5e23de64582a2c28709f9", blob.ObjectID.String())
			require.Equal(t, "Gemfile.lock", blob.BlobLocations[0].Path)
		} else {
			t.Fatal("unexpected change type")
		}
	}

	require.True(t, gotAdd)
	require.True(t, gotDelete)
}

func Test_DiffBlobsCanceled(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/diff-and-getblobs-basic/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(
		ctx,
		0,
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"),
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
	)
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	cancel() // NB: Cancel the context, same as if we were shutting down
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.EqualError(t, err, "spokesd: error fetching batch of blobs: context canceled")
}

func Test_DiffBlobs(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/diff-and-getblobs/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(
		ctx,
		0,
		treeish(t, repoID, "9c2c4bbd2adca3909f4f9551840cd46319cc3515"),
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
	)
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.NoError(t, err)

	stats := []string{""}
	for _, blob := range blobs {
		for _, loc := range blob.Locations() {
			var line strings.Builder
			switch loc.Change {
			case gitaccess.Add:
				line.WriteString("+")
				// All ADDS should have content
				require.NotNil(t, blob.Content, loc.Path)
				require.NotEmpty(t, blob.Content, loc.Path)
			case gitaccess.Delete:
				// DELETES DO have content now (changed for delta indexing)
				line.WriteString("-")
				require.NotNil(t, blob.Content, loc.Path)
				require.NotEmpty(t, blob.Content, loc.Path)
			default:
				t.Fatal("unexpected change type")
			}
			line.WriteString(" ")
			line.WriteString(loc.Path)
			line.WriteString(" ")
			line.WriteString(blob.ObjectID.String())
			stats = append(stats, line.String())
		}
	}
	sort.Strings(stats)
	require.Equal(t, `
+ .gitignore 8b00d48a83de48e54544be903c28d7aff32d7b25
+ Gemfile fffdea6edd0e3c0299d525660b8baf85cc2f24c3
+ Gemfile.lock 765ed12aef9947c93f61ea4a258bc41832fc06ae
+ Rakefile 88f6628c1840f1e559da99ecc395645dabe0a7bd
+ _config.yml a8a89a7ccb10122d0cbef66468d0ad72ed9ed0d0
+ _includes/download_button.html 978d7006be4a0aa058bf0eb7cd4d77f2d6f93d14
+ _layouts/default.html d96a923e4e73fccc40c98f841058603e7ac70de2
+ _layouts/markdown.html 6e9734f1257165dbb989234c44954c2d061656fd
+ _sass/git-tfs.scss eea52c488306a1ba0727bf2cfbf7a3ad9e69421b
+ config.rb 3683fc011e412215efd29e59df42bca7c0a5d5c3
+ index.md b797b05c16b2eb608ee953b4edad8923cd7a4dd9
+ javascripts/tabs.js 1c3de1a02b0365ee069052a29f64ef4ad8efc870
+ robots.txt d310d070b04b451b21afaffc735c4ace1ff29099
+ stylesheets/base.css 974b11dbd294b742b5813c271560a09ef0b7236a
+ stylesheets/git-tfs.css 731c242785be2380942d8d6dccbeea78946df85d
+ stylesheets/layout.css aff5b477e0999074d52ac29d72fc6fc43254c80a
+ stylesheets/skeleton.css ddc5e9345cca45eccf27364879027fefe4e1fce5
- _config.yml 008eb1091994f14bceb00451243d1b29f3a370ec
- _layouts/default.html 6d50f05a06a932fd9290be8713ec164a81504fbc
- assets/main.css 6ba8a73bcadc383be900dc2cc0303126808d5459
- index.md b355118a6435b754dba7772ea3d32205965c8355`, strings.Join(stats, "\n"))
}

func Test_Diff_DoesNotRetryFatalError(t *testing.T) {
	treesAPI := &mocks.FakeTreesAPI{}
	treesAPI.CompareTreesReturns(nil, twirp.NotFoundError("repository not found"))

	client := GitClient{
		spokesTreesAPI: treesAPI,
		opts:           &ClientOpts{Retries: 2},
	}

	_, err := client.Diff(
		context.Background(),
		0,
		treeish(t, repoID, "9c2c4bbd2adca3909f4f9551840cd46319cc3515"),
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
	)
	require.Error(t, err)
	require.Contains(t, err.Error(), "spokesd: failed to compare trees")
	require.True(t, IsRepoDeletedError(err))

	// It should not retry the diff (at this level)
	require.Equal(t, 1, treesAPI.CompareTreesCallCount())
}

func Test_Diff_MemoryLimitErrorIsFatal(t *testing.T) {
	treesAPI := &mocks.FakeTreesAPI{}
	treesAPI.CompareTreesReturns(nil, twirp.InternalError("git-diff-tree with memory limit: exit status 128"))

	client := GitClient{
		spokesTreesAPI: treesAPI,
		opts:           &ClientOpts{Retries: 2},
	}

	_, err := client.Diff(
		context.Background(),
		0,
		treeish(t, repoID, "9c2c4bbd2adca3909f4f9551840cd46319cc3515"),
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
	)
	require.Error(t, err)
	require.Contains(t, err.Error(), "spokesd: failed to compare trees")
	require.True(t, IsGitSystemError(err))

	// It should not retry the diff
	require.Equal(t, 1, treesAPI.CompareTreesCallCount())
}

func Test_DiffAcrossUnrelatedRepos(t *testing.T) {
	r, err := recorder.New("fixtures/diff-across-repos/git-tfs-go-git-fixtures")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	const (
		gitTfs            = types.RepoID(1)
		goGitFixtures     = types.RepoID(2)
		gitTfsHead        = "4b7d4830d01ddc2cff7cd0a8cd194d336bef9196"
		goGitFixturesHead = "2839385a06611036d7e8a7c196d47a90448016f9"
	)

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(context.Background(), 0, treeish(t, gitTfs, gitTfsHead), treeish(t, goGitFixtures, goGitFixturesHead))
	require.NoError(t, err)
	require.Len(t, diff[gitTfs], 24)
	require.Len(t, diff[goGitFixtures], 78)

	deletions := `.gitignore
.rvmrc
CNAME
Gemfile
Gemfile.lock
Rakefile
_config.yml
_includes/download_button.html
_layouts/default.html
_layouts/markdown.html
_sass/git-tfs.scss
config.rb
images/apple-touch-icon-114x114.png
images/apple-touch-icon-72x72.png
images/apple-touch-icon.png
images/favicon.ico
images/graphy.png
index.md
javascripts/tabs.js
robots.txt
stylesheets/base.css
stylesheets/git-tfs.css
stylesheets/layout.css
stylesheets/skeleton.css`

	additions := `.travis.yml
LICENSE
README.md
data.go
data/git-0a00a25543e6d732dbf4e8e9fec55c8e65fc4e8d.tgz
data/git-174be6bd4292c18160542ae6dc6704b877b8a01a.tgz
data/git-21504f6d2cc2ef0c9d6ebb8802c7b49abae40c1a.tgz
data/git-26baa505b9f6fb2024b9999c140b75514718c988.tgz
data/git-4870d54b5b04e43da8cf99ceec179d9675494af8.tgz
data/git-4e7600af05c3356e8b142263e127b76f010facfc.tgz
data/git-78c5fb882e76286d8201016cffee63ea7060a0c2.tgz
data/git-7a725350b88b05ca03541b59dd0649fda7f521f2.tgz
data/git-7cbde0ca02f13aedd5ec8b358ca17b1c0bf5ee64.tgz
data/git-935e5ac17c41c309c356639816ea0694a568c484.tgz
data/git-ab06771a67110b976953d34400d4dbc465ccd2d9.tgz
data/git-bf3fedcc8e20fd0dec9172987ceea0038d17b516.tgz
data/git-c0c7c57ab1753ddbd26cc45322299ddd12842794.tgz
data/git-cf717ccadce761d60bb4a8557a7b9a2efd23816a.tgz
data/git-df6781fd40b8f4911d70ce71f8387b991615cd6d.tgz
data/git-e1580a78f7d36791249df76df8a2a2613d629902.tgz
data/pack-0d3d824fb5c930e7e7e1f0f399f2976847d31fd3.idx
data/pack-0d3d824fb5c930e7e7e1f0f399f2976847d31fd3.pack
data/pack-0d9b6cfc261785837939aaede5986d7a7c212518.idx
data/pack-0d9b6cfc261785837939aaede5986d7a7c212518.pack
data/pack-135fe3d1ad828afe68706f1d481aedbcfa7a86d2.idx
data/pack-135fe3d1ad828afe68706f1d481aedbcfa7a86d2.pack
data/pack-1ea0b3971fd64fdcdf3282bfb58e8cf10095e4e6.idx
data/pack-1ea0b3971fd64fdcdf3282bfb58e8cf10095e4e6.pack
data/pack-21b33a26eb7ffbd35261149fe5d886b9debab7cb.idx
data/pack-21b33a26eb7ffbd35261149fe5d886b9debab7cb.pack
data/pack-29f304662fd64f102d94722cf5bd8802d9a9472c.idx
data/pack-29f304662fd64f102d94722cf5bd8802d9a9472c.pack
data/pack-3559b3b47e695b33b0913237a4df3357e739831c.idx
data/pack-3559b3b47e695b33b0913237a4df3357e739831c.pack
data/pack-3638209d310e10ea8d90c362d568be65dd5e03a6.idx
data/pack-3638209d310e10ea8d90c362d568be65dd5e03a6.pack
data/pack-36ef7a2296bfd526020340d27c5e1faa805d8d38.idx
data/pack-36ef7a2296bfd526020340d27c5e1faa805d8d38.pack
data/pack-4ec6344877f494690fc800aceaf2ca0e86786acb.idx
data/pack-4ec6344877f494690fc800aceaf2ca0e86786acb.pack
data/pack-61f0ee9c75af1f9678e6f76ff39fbe372b6f1c45.idx
data/pack-61f0ee9c75af1f9678e6f76ff39fbe372b6f1c45.pack
data/pack-63bbc2e1bde392e2205b30fa3584ddb14ef8bd41.idx
data/pack-63bbc2e1bde392e2205b30fa3584ddb14ef8bd41.pack
data/pack-769137af7784db501bca677fbd56fef8b52515b7.idx
data/pack-769137af7784db501bca677fbd56fef8b52515b7.pack
data/pack-7861f2632868833a35fe5e4ab94f99638ec5129b.idx
data/pack-7861f2632868833a35fe5e4ab94f99638ec5129b.pack
data/pack-9733763ae7ee6efcf452d373d6fff77424fb1dcc.idx
data/pack-9733763ae7ee6efcf452d373d6fff77424fb1dcc.pack
data/pack-a3fed42da1e8189a077c0e6846c040dcf73fc9dd.idx
data/pack-a3fed42da1e8189a077c0e6846c040dcf73fc9dd.pack
data/pack-b68617dd8637fe6409d9842825a843a1d9a6e484.idx
data/pack-b68617dd8637fe6409d9842825a843a1d9a6e484.pack
data/pack-bb8ee94710d3fa39379a630f76812c187217b312.idx
data/pack-bb8ee94710d3fa39379a630f76812c187217b312.pack
data/pack-c544593473465e6315ad4182d04d366c4592b829.idx
data/pack-c544593473465e6315ad4182d04d366c4592b829.pack
data/pack-ee4fef0ef8be5053ebae4ce75acf062ddf3031fb.pack
data/pack-f2e0a8889a746f7600e07d2246a2e29a72f696be.idx
data/pack-f2e0a8889a746f7600e07d2246a2e29a72f696be.pack
data/worktree-363d996b02d9c3b598f0176619f5c6a44a82480a.tgz
data/worktree-7203669c66103305e56b9dcdf940a7fbeb515f28.tgz
data/worktree-8b4d55c85677b6b94bef2e46832ed2174ed6ecaf.tgz
data/worktree-a6b6ff89c593f042347113203ead1c14ab5733ce.tgz
data/worktree-d2e42ddd68eacbb6034e7724e0dd4117ff1f01ee.tgz
data/worktree-e3b91f99d8d050cac81d84fbef89172f58eeb745.tgz
fixtures.go
fixtures_test.go
go.mod
go.sum
internal/tgz/fixtures/invalid-gzip.tgz
internal/tgz/fixtures/not-a-tar.tgz
internal/tgz/fixtures/test-01.tgz
internal/tgz/fixtures/test-02.tgz
internal/tgz/fixtures/test-03.tgz
internal/tgz/tgz.go
internal/tgz/tgz_test.go`

	deletedPaths := []string{}
	addedPaths := []string{}
	for _, diffEntries := range diff {
		for _, entry := range diffEntries {
			switch entry.Change {
			case gitaccess.Add:
				addedPaths = append(addedPaths, entry.Path)
			case gitaccess.Delete:
				deletedPaths = append(deletedPaths, entry.Path)
			default:
				require.Fail(t, "well, that shouldn't have happened")
			}
		}
	}

	require.ElementsMatch(t, strings.Split(deletions, "\n"), deletedPaths)
	require.ElementsMatch(t, strings.Split(additions, "\n"), addedPaths)
}

func Test_DiffAcrossDuplicatedRepos(t *testing.T) {
	r, err := recorder.New("fixtures/diff-across-repos/go-git-fixtures-go-git-fixtures-2")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	const (
		goGitFixtures     = types.RepoID(2)
		goGitFixtures2    = types.RepoID(3)
		goGitFixturesHead = "2839385a06611036d7e8a7c196d47a90448016f9"
	)

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(context.Background(), 0, treeish(t, goGitFixtures, goGitFixturesHead), treeish(t, goGitFixtures2, goGitFixturesHead))

	require.NoError(t, err)
	require.Empty(t, diff[goGitFixtures])
	require.Empty(t, diff[goGitFixtures2])
}

func Test_InterRepoDiffNotFound(t *testing.T) {
	const (
		repoOneID = types.RepoID(1)
		repoTwoID = types.RepoID(2)
		base      = "9c2c4bbd2adca3909f4f9551840cd46319cc3515"
		head      = "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"
	)

	var tests = []struct {
		name     string
		baseResp *spokesTrees.ListTreesResponse
		baseErr  error
		headErr  error
		expected func(err error) bool
	}{
		{
			name:     "base repo not found",
			baseErr:  twirp.NotFoundError("repo/wiki not found"),
			expected: IsInvalidDiffBaseError,
		},
		{
			name:     "base commit not found",
			baseErr:  twirp.NotFoundError(fmt.Sprintf("object %s not found", base)),
			expected: IsInvalidDiffBaseError,
		},
		{
			name: "head repo not found",
			baseResp: &spokesTrees.ListTreesResponse{
				Entries: []*spokes.TreeEntry{
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: base}, 0),
						Path:   &spokes.Path{Name: []byte("duplicated.txt")},
					},
				},
			},
			headErr:  twirp.NotFoundError("repo/wiki not found"),
			expected: IsRepoDeletedError,
		},
		{
			name: "head commit not found",
			baseResp: &spokesTrees.ListTreesResponse{
				Entries: []*spokes.TreeEntry{
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: base}, 0),
						Path:   &spokes.Path{Name: []byte("duplicated.txt")},
					},
				},
			},
			headErr:  twirp.NotFoundError(fmt.Sprintf("object %s not found", head)),
			expected: IsInvalidCommitError,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			treesAPI := &mocks.FakeTreesAPI{}
			treesAPI.ListTreesReturnsOnCall(0, test.baseResp, test.baseErr)
			if test.headErr != nil {
				treesAPI.ListTreesReturnsOnCall(1, nil, test.headErr)
			}

			client := GitClient{
				spokesTreesAPI: treesAPI,
				opts:           &ClientOpts{Retries: 2},
			}

			_, err := client.Diff(
				context.Background(),
				0,
				treeish(t, repoOneID, base),
				treeish(t, repoTwoID, head),
			)
			require.Error(t, err)
			require.Contains(t, err.Error(), "spokesd: failed to compare trees")
			require.True(t, test.expected(err), "unexpected error: %+v", err)

			// It should not retry the diff (at this level), the first failure stops the operation
			if test.headErr != nil {
				require.Equal(t, 2, treesAPI.ListTreesCallCount())
			} else {
				require.Equal(t, 1, treesAPI.ListTreesCallCount())
			}
		})
	}
}

func Test_InterRepoDiffCases(t *testing.T) {
	const repoA = types.RepoID(1)
	const repoB = types.RepoID(2)

	treesAPI := &mocks.FakeTreesAPI{}
	treesAPI.ListTreesStub = func(cxt context.Context, req *spokesTrees.ListTreesRequest) (*spokesTrees.ListTreesResponse, error) {
		if req.Repository.Id == uint64(repoA) {
			resp := &spokesTrees.ListTreesResponse{
				Entries: []*spokes.TreeEntry{
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, 0),
						Path:   &spokes.Path{Name: []byte("duplicated.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}, 0),
						Path:   &spokes.Path{Name: []byte("same-blob-different-mode.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "cccccccccccccccccccccccccccccccccccccccc"}, 0),
						Path:   &spokes.Path{Name: []byte("removed-in-b.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "dddddddddddddddddddddddddddddddddddddddd"}, 0),
						Path:   &spokes.Path{Name: []byte("different-path.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
						Path:   &spokes.Path{Name: []byte("blob-at-path-will-be-updated.txt")},
					},
				},
			}

			return resp, nil
		}

		if req.Repository.Id == uint64(repoB) {
			resp := &spokesTrees.ListTreesResponse{
				Entries: []*spokes.TreeEntry{
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}, 0),
						Path:   &spokes.Path{Name: []byte("duplicated.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_755},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}, 0),
						Path:   &spokes.Path{Name: []byte("same-blob-different-mode.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "dddddddddddddddddddddddddddddddddddddddd"}, 0),
						Path:   &spokes.Path{Name: []byte("path-different.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"}, 0),
						Path:   &spokes.Path{Name: []byte("added-in-b.txt")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o160_000}, // submodule: should be excluded
						Object: spokes.NewCommitObject(&spokes.ObjectID{Id: "ffffffffffffffffffffffffffffffffffffffff"}, 0),
						Path:   &spokes.Path{Name: []byte("deps/other-repo")},
					},
					{
						Mode:   &spokes.Mode{Mode: 0o100_644},
						Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a222222222222222222222222222222222222222"}, 0),
						Path:   &spokes.Path{Name: []byte("blob-at-path-will-be-updated.txt")},
					},
				},
			}

			return resp, nil
		}

		return nil, fmt.Errorf("should get here: repo: %+v", req.Repository)
	}

	client := GitClient{
		spokesTreesAPI: treesAPI,
		opts:           &ClientOpts{},
	}

	diff, err := client.Diff(context.Background(), 0, treeish(t, repoA, helpers.UniqueOID(t).String()), treeish(t, repoB, helpers.UniqueOID(t).String()))
	require.NoError(t, err)

	expected := []*gitaccess.DiffEntry{
		{
			Path:   "different-path.txt",
			OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
			Change: gitaccess.Delete,
		},
		{
			Path:   "removed-in-b.txt",
			OID:    helpers.OID(t, "cccccccccccccccccccccccccccccccccccccccc"),
			Change: gitaccess.Delete,
		},
		{
			Path:   "blob-at-path-will-be-updated.txt",
			OID:    helpers.OID(t, "a111111111111111111111111111111111111111"),
			Change: gitaccess.Delete,
		},
	}
	require.ElementsMatch(t, expected, diff[repoA])

	expected = []*gitaccess.DiffEntry{
		{
			Path:   "path-different.txt",
			OID:    helpers.OID(t, "dddddddddddddddddddddddddddddddddddddddd"),
			Change: gitaccess.Add,
		},
		{
			Path:   "added-in-b.txt",
			OID:    helpers.OID(t, "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"),
			Change: gitaccess.Add,
		},
		{
			Path:   "blob-at-path-will-be-updated.txt",
			OID:    helpers.OID(t, "a222222222222222222222222222222222222222"),
			Change: gitaccess.Add,
		},
	}
	require.ElementsMatch(t, expected, diff[repoB])
}

func Test_IntraRepoDiffNotFound(t *testing.T) {
	// Two cases to test here:
	// - nil base => does list tree (as head)
	// - base, head => does compare tree
	const (
		repoID = types.RepoID(1)
		base   = "9c2c4bbd2adca3909f4f9551840cd46319cc3515"
		head   = "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"
	)

	var tests = []struct {
		name     string
		base     *gitaccess.Treeish // nil or not
		err      error
		expected func(err error) bool
	}{
		{
			name:     "list trees does not find repo",
			err:      twirp.NotFoundError("repo/wiki not found"),
			expected: IsRepoDeletedError,
		},
		{
			name:     "list head tree does not find commit",
			err:      twirp.NotFoundError(fmt.Sprintf("object %s not found", head)),
			expected: IsInvalidCommitError,
		},
		{
			name:     "compare trees does not find base commit",
			base:     treeish(t, repoID, base),
			err:      twirp.NotFoundError(fmt.Sprintf("object %s not found", base)),
			expected: IsInvalidDiffBaseError,
		},
		{
			name:     "compare trees does not find head commit",
			base:     treeish(t, repoID, base),
			err:      twirp.NotFoundError(fmt.Sprintf("object %s not found", head)),
			expected: IsInvalidCommitError,
		},
		{
			name:     "compare trees does not find repo",
			base:     treeish(t, repoID, base),
			err:      twirp.NotFoundError("repo/wiki not found"),
			expected: IsRepoDeletedError,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			treesAPI := &mocks.FakeTreesAPI{}
			treesAPI.ListTreesReturns(nil, test.err)
			treesAPI.CompareTreesReturns(nil, test.err)

			client := GitClient{
				spokesTreesAPI: treesAPI,
				opts:           &ClientOpts{Retries: 2},
			}

			_, err := client.Diff(context.Background(), 0, test.base, treeish(t, repoID, head))

			require.Error(t, err)
			require.Contains(t, err.Error(), "spokesd: failed to compare trees")
			require.True(t, test.expected(err), "unexpected error: %+v", err)

			// It should not retry the diff (at this level), the first failure stops the operation
			if test.base == nil {
				require.Equal(t, 1, treesAPI.ListTreesCallCount())
			} else {
				require.Equal(t, 1, treesAPI.CompareTreesCallCount())
			}
		})
	}
}

func Test_InterRepoDiffCasesWithLocationLimit(t *testing.T) {
	const repoAID = types.RepoID(1)
	const repoBID = types.RepoID(2)

	locationLimit := 1

	var tests = []struct {
		name             string
		repoAEntries     []*spokes.TreeEntry
		repoBEntries     []*spokes.TreeEntry
		expectedErr      error
		expectedRepoDiff map[types.RepoID][]*gitaccess.DiffEntry
	}{
		{
			name:         "no diff",
			repoAEntries: []*spokes.TreeEntry{},
			repoBEntries: []*spokes.TreeEntry{},
			expectedErr:  nil,
			expectedRepoDiff: map[types.RepoID][]*gitaccess.DiffEntry{
				repoAID: {},
				repoBID: {},
			},
		},
		{
			name: "base and head diff entries are within limit",
			repoAEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file.txt")},
				},
			},
			repoBEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a222222222222222222222222222222222222222"}, 0),
					Path:   &spokes.Path{Name: []byte("other-new-file.txt")},
				},
			},
			expectedErr: nil,
			expectedRepoDiff: map[types.RepoID][]*gitaccess.DiffEntry{
				repoAID: {
					{
						Path:   "new-file.txt",
						OID:    helpers.OID(t, "a111111111111111111111111111111111111111"),
						Change: gitaccess.Delete,
					},
				},
				repoBID: {
					{
						Path:   "other-new-file.txt",
						OID:    helpers.OID(t, "a222222222222222222222222222222222222222"),
						Change: gitaccess.Add,
					},
				},
			},
		},
		{
			name: "base diff entries exceed limit but head diff entries are within limit",
			repoAEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-1.txt")},
				},
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a333333333333333333333333333333333333333"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-3.txt")},
				},
			},
			repoBEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a222222222222222222222222222222222222222"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-2.txt")},
				},
			},
			expectedErr:      LocationLimitExceededError,
			expectedRepoDiff: nil,
		},
		{
			name: "base diff entries are within limit but head diff entries exceed limit",
			repoAEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-1.txt")},
				},
			},
			repoBEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a222222222222222222222222222222222222222"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-2.txt")},
				},
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a333333333333333333333333333333333333333"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-3.txt")},
				},
			},
			expectedErr:      LocationLimitExceededError,
			expectedRepoDiff: nil,
		},
		{
			name: "base and head diff entries both exceed limit",
			repoAEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-1.txt")},
				},
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a444444444444444444444444444444444444444"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-4.txt")},
				},
			},
			repoBEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a222222222222222222222222222222222222222"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-2.txt")},
				},
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a333333333333333333333333333333333333333"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-3.txt")},
				},
			},
			expectedErr:      LocationLimitExceededError,
			expectedRepoDiff: nil,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			treesAPI := &mocks.FakeTreesAPI{}
			treesAPI.ListTreesStub = func(cxt context.Context, req *spokesTrees.ListTreesRequest) (*spokesTrees.ListTreesResponse, error) {
				if req.Repository.Id == uint64(repoAID) {
					resp := &spokesTrees.ListTreesResponse{Entries: test.repoAEntries}
					return resp, nil
				}

				if req.Repository.Id == uint64(repoBID) {
					resp := &spokesTrees.ListTreesResponse{Entries: test.repoBEntries}
					return resp, nil
				}

				return nil, fmt.Errorf("should not get here: repo: %+v", req.Repository)
			}
			client := GitClient{
				spokesTreesAPI: treesAPI,
				opts:           &ClientOpts{},
			}

			repoDiff, err := client.Diff(context.Background(), locationLimit, treeish(t, repoAID, helpers.UniqueOID(t).String()), treeish(t, repoBID, helpers.UniqueOID(t).String()))
			if test.expectedErr != nil {
				require.Error(t, err)
				require.ErrorIs(t, err, test.expectedErr)
			} else {
				require.NoError(t, err)
				require.Equal(t, gitaccess.RepoDiff(test.expectedRepoDiff), repoDiff)
			}
		})
	}
}

func Test_IntraRepoDiffCasesFirstTimeIngestWithLocationLimit(t *testing.T) {
	const repoAID = types.RepoID(1)

	locationLimit := 1

	var tests = []struct {
		name             string
		repoAEntries     []*spokes.TreeEntry
		expectedErr      error
		expectedRepoDiff map[types.RepoID][]*gitaccess.DiffEntry
	}{
		{
			name:         "no diff",
			repoAEntries: []*spokes.TreeEntry{},
			expectedErr:  nil,
			expectedRepoDiff: map[types.RepoID][]*gitaccess.DiffEntry{
				repoAID: {},
			},
		},
		{
			name: "head diff entries are within limit",
			repoAEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file.txt")},
				},
			},
			expectedErr: nil,
			expectedRepoDiff: map[types.RepoID][]*gitaccess.DiffEntry{
				repoAID: {
					{
						Path:   "new-file.txt",
						OID:    helpers.OID(t, "a111111111111111111111111111111111111111"),
						Change: gitaccess.Add,
					},
				},
			},
		},
		{
			name: "head diff entries exceed limit",
			repoAEntries: []*spokes.TreeEntry{
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a111111111111111111111111111111111111111"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-1.txt")},
				},
				{
					Mode:   &spokes.Mode{Mode: 0o100_644},
					Object: spokes.NewBlobObject(&spokes.ObjectID{Id: "a333333333333333333333333333333333333333"}, 0),
					Path:   &spokes.Path{Name: []byte("new-file-3.txt")},
				},
			},
			expectedErr:      LocationLimitExceededError,
			expectedRepoDiff: nil,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			treesAPI := &mocks.FakeTreesAPI{}
			treesAPI.ListTreesStub = func(cxt context.Context, req *spokesTrees.ListTreesRequest) (*spokesTrees.ListTreesResponse, error) {
				resp := &spokesTrees.ListTreesResponse{Entries: test.repoAEntries}
				return resp, nil
			}
			client := GitClient{
				spokesTreesAPI: treesAPI,
				opts:           &ClientOpts{},
			}

			// To simulate a first time ingest, the base treeish must be nil.
			baseTreeish := &gitaccess.Treeish{RepoID: repoAID, Treeish: nil}
			repoDiff, err := client.Diff(context.Background(), locationLimit, baseTreeish, treeish(t, repoAID, helpers.UniqueOID(t).String()))
			if test.expectedErr != nil {
				require.Error(t, err)
				require.ErrorIs(t, err, test.expectedErr)
			} else {
				require.NoError(t, err)
				require.Equal(t, gitaccess.RepoDiff(test.expectedRepoDiff), repoDiff)
			}
		})
	}
}

func Test_IntraRepoDiffCases(t *testing.T) {
	const repoID = types.RepoID(1)

	treesAPI := &mocks.FakeTreesAPI{}
	treesAPI.CompareTreesReturns(
		&spokesTrees.CompareTreesResponse{
			Entries: []*spokes.DiffEntry{
				{
					DestinationMode: &spokes.Mode{Mode: 0o100_644},
					DestinationOid:  &spokes.ObjectID{Id: "a111111111111111111111111111111111111111"},
					Destination:     &spokes.Path{Name: []byte("new-file.txt")},
					Status:          spokes.DiffEntry_STATUS_ADDITION,
				},
				// same-blob-different-mode.txt will be excluded because it is a noop diff from blackbird's perspective
				{
					SourceMode:      &spokes.Mode{Mode: 0o100_755},
					SourceOid:       &spokes.ObjectID{Id: "a222222222222222222222222222222222222222"},
					Source:          &spokes.Path{Name: []byte("same-blob-different-mode.txt")},
					DestinationMode: &spokes.Mode{Mode: 0o100_644},
					DestinationOid:  &spokes.ObjectID{Id: "a222222222222222222222222222222222222222"},
					Destination:     &spokes.Path{Name: []byte("same-blob-different-mode.txt")},
					Status:          spokes.DiffEntry_STATUS_MODIFICATION,
				},
				{
					SourceMode: &spokes.Mode{Mode: 0o100_644},
					SourceOid:  &spokes.ObjectID{Id: "a333333333333333333333333333333333333333"},
					Source:     &spokes.Path{Name: []byte("deleted-file.txt")},
					Status:     spokes.DiffEntry_STATUS_DELETION,
				},
				{
					SourceMode:      &spokes.Mode{Mode: 0o100_644},
					SourceOid:       &spokes.ObjectID{Id: "a444444444444444444444444444444444444444"},
					Source:          &spokes.Path{Name: []byte("old-path.txt")},
					DestinationMode: &spokes.Mode{Mode: 0o100_644},
					DestinationOid:  &spokes.ObjectID{Id: "a444444444444444444444444444444444444444"},
					Destination:     &spokes.Path{Name: []byte("new-path.txt")},
					Status:          spokes.DiffEntry_STATUS_RENAME,
				},
				{
					DestinationMode: &spokes.Mode{Mode: 0o160_000},
					DestinationOid:  &spokes.ObjectID{Id: "a555555555555555555555555555555555555555"},
					Destination:     &spokes.Path{Name: []byte("deps/new-submodule")},
					Status:          spokes.DiffEntry_STATUS_ADDITION,
				},
				{
					SourceMode: &spokes.Mode{Mode: 0o160_000},
					SourceOid:  &spokes.ObjectID{Id: "a555555555555555555555555555555555555555"},
					Source:     &spokes.Path{Name: []byte("deps/deleted-submodule")},
					Status:     spokes.DiffEntry_STATUS_DELETION,
				},
				{
					SourceMode:      &spokes.Mode{Mode: 0o100_644},
					SourceOid:       &spokes.ObjectID{Id: "a666666666666666666666666666666666666666"},
					Source:          &spokes.Path{Name: []byte("different-type.txt")},
					DestinationMode: &spokes.Mode{Mode: 0o120_000},
					DestinationOid:  &spokes.ObjectID{Id: "a777777777777777777777777777777777777777"},
					Destination:     &spokes.Path{Name: []byte("different-type.txt")},
					Status:          spokes.DiffEntry_STATUS_TYPE,
				},
			},
		},
		nil,
	)

	client := GitClient{
		spokesTreesAPI: treesAPI,
		opts:           &ClientOpts{},
	}

	diff, err := client.Diff(context.Background(), 0, treeish(t, repoID, helpers.UniqueOID(t).String()), treeish(t, repoID, helpers.UniqueOID(t).String()))
	require.NoError(t, err)

	expected := []*gitaccess.DiffEntry{
		{
			Path:   "new-file.txt",
			OID:    helpers.OID(t, "a111111111111111111111111111111111111111"),
			Change: gitaccess.Add,
		},
		{
			Path:   "deleted-file.txt",
			OID:    helpers.OID(t, "a333333333333333333333333333333333333333"),
			Change: gitaccess.Delete,
		},
		{
			Path:   "old-path.txt",
			OID:    helpers.OID(t, "a444444444444444444444444444444444444444"),
			Change: gitaccess.Delete,
		},
		{
			Path:   "new-path.txt",
			OID:    helpers.OID(t, "a444444444444444444444444444444444444444"),
			Change: gitaccess.Add,
		},
		{
			Path:   "different-type.txt",
			OID:    helpers.OID(t, "a666666666666666666666666666666666666666"),
			Change: gitaccess.Delete,
		},
		{
			Path:   "different-type.txt",
			OID:    helpers.OID(t, "a777777777777777777777777777777777777777"),
			Change: gitaccess.Add,
		},
	}

	require.ElementsMatch(t, expected, diff[repoID])
}

func Test_GetTreeOIDForCommit(t *testing.T) {
	r, err := recorder.New("fixtures/gettreeoidforcommit/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	treeOID, err := client.GetTreeOIDForCommit(context.Background(), repoID, helpers.OID(t, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"))
	require.NoError(t, err)
	require.Equal(t, "0d694eca133d70d55320fe68d82b1501c92306ea", treeOID.String())
}

func Test_GetTreeOIDForCommitNotFoundDoesNotRetry(t *testing.T) {
	commitsAPI := &mocks.FakeCommitsAPI{}
	commitsAPI.ListCommitsReturns(nil, twirp.NotFoundError("commit not found"))

	client := GitClient{
		spokesCommitsAPI: commitsAPI,
		opts:             &ClientOpts{Retries: 2},
	}

	_, err := client.GetTreeOIDForCommit(context.Background(), repoID, helpers.OID(t, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"))
	require.Error(t, err)
	require.Contains(t, err.Error(), "spokesd: failed to get tree OID for commit")

	// It should not retry the diff
	require.Equal(t, 1, commitsAPI.ListCommitsCallCount())
}

func Test_GetTreeOIDForCommitWithInvalidObjectIsFatal(t *testing.T) {
	commitsAPI := &mocks.FakeCommitsAPI{}
	commitsAPI.ListCommitsReturns(
		&commits.ListCommitsResponse{
			Commits: []*commits.CommitItem{
				{
					Oid: spokes.NewObjectID("33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"),
					CommitItemContent: &commits.CommitItem_Error{
						Error: "commit object too long (29179869 bytes)",
					},
				},
			},
		},
		nil,
	)

	client := GitClient{
		spokesCommitsAPI: commitsAPI,
		opts:             &ClientOpts{Retries: 2},
	}

	_, err := client.GetTreeOIDForCommit(context.Background(), repoID, helpers.OID(t, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"))
	require.Error(t, err)
	require.Contains(t, err.Error(), "spokesd: failed to get tree OID for commit")
	require.True(t, IsInvalidCommitError(err))

	// It should not retry the diff
	require.Equal(t, 1, commitsAPI.ListCommitsCallCount())
}

// GetBlobs with no prior state returns all interesting blobs in the repo
func Test_GetAllBlobsForARepo(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/getblobs/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(ctx, 0, nil, &gitaccess.Treeish{RepoID: repoID, Treeish: spokes.NewTreeishWithReference(spokes.DefaultBranch())})
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.NoError(t, err)

	added, deleted := fetchAddedDeletedPaths(t, blobs)
	require.ElementsMatch(t, []string{
		"_config.yml",
		"_includes/download_button.html",
		"_layouts/default.html",
		"_layouts/markdown.html",
		"_sass/git-tfs.scss",
		".gitignore",
		".rvmrc",
		"CNAME",
		"config.rb",
		"Gemfile.lock",
		"Gemfile",
		"index.md",
		"javascripts/tabs.js",
		"Rakefile",
		"robots.txt",
		"stylesheets/base.css",
		"stylesheets/git-tfs.css",
		"stylesheets/layout.css",
		"stylesheets/skeleton.css",
	}, added)
	require.ElementsMatch(t, []string{}, deleted)
}

// Incremental GetBlobs where the prior state is identical to the current state
// of the repo resulting in zero blobs returned.
func Test_GetAllBlobsForARepoIncrNoop(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/getblobsincr-noop/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	// Defined in: deps/spokes-proto/docker-compose.yml
	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(ctx,
		0,
		treeish(t, repoID, "22d257b88877f0ef2c4bd00dd7fcb765127db322"), // refs/heads/master
		&gitaccess.Treeish{RepoID: repoID, Treeish: spokes.NewTreeishWithReference(spokes.DefaultBranch())},
	)
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.NoError(t, err)

	blobCount := 0
	locationCount := 0
	for _, b := range blobs {
		require.True(t, len(b.Locations()) > 0, "must have at least one location")
		blobCount += 1
		locationCount += len(b.Locations())
	}

	require.Equal(t, 0, locationCount)
	require.Equal(t, 0, blobCount)
}

// Incremental GetBlobs where the prior state is one commit behind on the master
// branch. A single file was edited (Gemfile.lock) resulting in a delete and an
// add. The delete is expected to have no content (no spokesd call to stream the
// blob).
func Test_GetAllBlobsForARepoIncrSimple(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/getblobsincrsimple/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(ctx,
		0,
		treeish(t, repoID, "8ec6c330168e3f007b4d871f04a9eb228688bdc9"), // NB: One commit behind
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"), // refs/heads/master
	)
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.NoError(t, err)

	added, deleted := fetchAddedDeletedPaths(t, blobs)
	require.ElementsMatch(t, []string{
		"Gemfile.lock",
	}, added)
	require.ElementsMatch(t, []string{
		"Gemfile.lock",
	}, deleted)
}

func Test_GetAllBlobsForARepoIncr(t *testing.T) {
	ctx := context.Background()
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	r, err := recorder.New("fixtures/getblobsincr/git-tfs")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(ctx,
		0,
		treeish(t, repoID, "f664d7032cc8684a53c2a023865ba01af9de0287"), // refs/heads/js-release-button
		treeish(t, repoID, "33863ef598ddfbabd1bd7be9a80b3734c2cd09c2"), // refs/heads/master
	)
	require.NoError(t, err)
	blobs := []*gitaccess.BlobContentChange{}
	err = client.GetBlobsForDiff(ctx, cancel, diff, func(b *gitaccess.BlobContentChange) { blobs = append(blobs, b) })
	require.NoError(t, err)

	added, deleted := fetchAddedDeletedPaths(t, blobs)
	require.ElementsMatch(t, []string{
		"Gemfile",
		"Gemfile.lock",
		"Rakefile",
		"_config.yml",
		"_includes/download_button.html",
		"_layouts/default.html",
		"_sass/git-tfs.scss",
		"index.md",
		"stylesheets/git-tfs.css",
	}, added)
	require.ElementsMatch(t, []string{
		"Gemfile",
		"Gemfile.lock",
		"Rakefile",
		"_config.yml",
		"_includes/download_button.html",
		"_layouts/default.html",
		"_sass/git-tfs.scss",
		"index.md",
		"javascripts/releases.js", // deleted entirely
		// "javascripts/spin.min.js", // NB: Never included in the first place (generated)
		"stylesheets/git-tfs.css",
	}, deleted)
}

func Test_DiffHeadRepoNotFound(t *testing.T) {
	ctx := context.Background()
	r, err := recorder.New("fixtures/getblobs/repo-not-found")
	require.NoError(t, err)
	defer r.Stop() //nolint:errcheck
	httpClient := &http.Client{Transport: r}

	client := New(spokesdURL, httpClient, nil)
	diff, err := client.Diff(ctx, 0, nil, &gitaccess.Treeish{RepoID: unknownRepoID, Treeish: spokes.NewTreeishWithReference(spokes.DefaultBranch())})
	require.Error(t, err)
	require.Nil(t, diff)
	require.Contains(t, err.Error(), "twirp error not_found: network not found for repository/wiki")
	require.True(t, IsRepoDeletedError(err))
}

func Test_FailedToConnectToSpokes(t *testing.T) {
	ctx := context.Background()
	client := New("http://not-a-server:8081", http.DefaultClient, nil)
	diff, err := client.Diff(ctx, 0, nil, &gitaccess.Treeish{RepoID: unknownRepoID, Treeish: spokes.NewTreeishWithReference(spokes.DefaultBranch())})
	require.Error(t, err)
	require.Nil(t, diff)
	require.Contains(t, err.Error(), "spokesd: failed to compare trees")
}

func Test_ResolveBlobs(t *testing.T) {
	type test struct {
		name     string
		input    gitaccess.RepoBlobsMap
		expected gitaccess.RepoBlobsMap
	}

	tests := []test{
		{
			name: "blob does not exist",
			input: gitaccess.RepoBlobsMap{
				1: gitaccess.BlobSet{
					helpers.OID(t, "5cd6fa98985a60e29918f6bc2a362ec68cc0335f"): true, // path: CNAME
					helpers.OID(t, "4b7d4830d01ddc2cff7cd0a8cd194d336bef9196"): true, // This is a commit SHA (not a blob)
				},
			},
			expected: gitaccess.RepoBlobsMap{
				1: gitaccess.BlobSet{
					helpers.OID(t, "4b7d4830d01ddc2cff7cd0a8cd194d336bef9196"): true,
				},
			},
		},
		{
			name: "everything resolves",
			input: gitaccess.RepoBlobsMap{
				1: gitaccess.BlobSet{
					helpers.OID(t, "5cd6fa98985a60e29918f6bc2a362ec68cc0335f"): true, // path: CNAME
					helpers.OID(t, "fffdea6edd0e3c0299d525660b8baf85cc2f24c3"): true, // path: Gemfile
				},
			},
			expected: gitaccess.RepoBlobsMap{},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			fixture := fmt.Sprintf("fixtures/resolve-blobs/%s", strings.ReplaceAll(test.name, " ", "-"))
			r, err := recorder.New(fixture)
			require.NoError(t, err)
			defer r.Stop() //nolint:errcheck
			httpClient := &http.Client{Transport: r}
			client := New(spokesdURL, httpClient, nil)

			err = client.ResolveBlobs(context.Background(), test.input)

			require.NoError(t, err)
			for id, set := range test.input {
				require.Equal(t, test.expected[id], set)
			}
		})
	}
}

func fetchAddedDeletedPaths(t *testing.T, blobs []*gitaccess.BlobContentChange) ([]string, []string) {
	pathsAdded := []string{}
	pathsDeleted := []string{}
	for _, b := range blobs {
		require.True(t, len(b.Locations()) > 0, "must have at least one location")
		for _, loc := range b.Locations() {

			if loc.Change == gitaccess.Add {
				pathsAdded = append(pathsAdded, loc.Path)
				assert.NotNil(t, b.Content)
			} else {
				pathsDeleted = append(pathsDeleted, loc.Path)
				// NB: Deleted blobs must include content for IsGenerated check in delta indexing
				assert.NotNil(t, b.Content)
			}
		}
	}

	sort.Strings(pathsAdded)
	sort.Strings(pathsDeleted)

	return pathsAdded, pathsDeleted
}

func treeish(t *testing.T, repoID types.RepoID, sha string) *gitaccess.Treeish {
	t.Helper()

	return &gitaccess.Treeish{
		RepoID:  repoID,
		Treeish: spokes.NewTreeishWithObjectID(spokes.NewObjectID(sha)),
	}
}

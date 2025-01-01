package spokesd

import (
	"context"
	_ "embed"
	"fmt"
	"strings"
	"testing"

	spokesTrees "github.com/github/spokes-proto/gen/go/v1/trees"
	spokes "github.com/github/spokes-proto/gen/go/v1/types"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/test/mocks"
	"github.com/github/blackbird-mw/internal/types"
)

//go:embed repo_475454893_ls_tree_a4394bba.txt
var baseLsTree string

//go:embed repo_481331442_ls_tree_4300d8ee.txt
var headLsTree string

// This test covers a cache-based delta index that went bad. I did not find any
// problems with this code but it's a useful test so I'm keeping it.
func Test_InterRepoDiff(t *testing.T) {
	const baseRepo = types.RepoID(1)
	const headRepo = types.RepoID(2)

	treesAPI := &mocks.FakeTreesAPI{}
	treesAPI.ListTreesStub = func(cxt context.Context, req *spokesTrees.ListTreesRequest) (*spokesTrees.ListTreesResponse, error) {
		if req.Repository.Id == uint64(baseRepo) {
			return &spokesTrees.ListTreesResponse{Entries: treeFromLsTree(t, baseLsTree)}, nil
		}

		if req.Repository.Id == uint64(headRepo) {
			return &spokesTrees.ListTreesResponse{Entries: treeFromLsTree(t, headLsTree)}, nil
		}

		return nil, fmt.Errorf("should get here: repo: %+v", req.Repository)
	}

	client := GitClient{
		spokesTreesAPI: treesAPI,
		opts:           &ClientOpts{},
	}

	diff, err := client.Diff(context.Background(), 0, treeish(t, baseRepo, helpers.UniqueOID(t).String()), treeish(t, headRepo, helpers.UniqueOID(t).String()))
	require.NoError(t, err)

	// These oid/paths were supposed to be deleted, but weren't.
	// https://github.com/github/blackbird-mw/issues/1963
	blobPaths := []struct {
		sha  string
		path string
	}{
		{"f3069fd6f87183c1e9c9d566ad56c9df13f85fa6", "argo-cd-apps/overlays/staging/kustomization.yaml"},
		{"a93cc2dd9b00997bdc967aa2723e9e8fc5abe5b3", "components/spi-vault/kustomization.yaml"},
		{"9e835d18bf8553500698fa2be70adf419797f178", "argo-cd-apps/overlays/development/kustomization.yaml"},
		{"91deff051ac55202d7fbb56966292f3f115fab37", "components/spi/overlays/staging/base/kustomization.yaml"},
		{"74ed4e20500b51c2ec5c57dd154bd70398a6bbcc", "components/monitoring/grafana/base/spi/kustomization.yaml"},
		{"25bdbea061fdc1adb7537205bd95b26a612f1ace", "components/spi/overlays/development/kustomization.yaml"},
	}

	for _, blobPath := range blobPaths {
		found := false
		for _, entry := range diff[baseRepo] {
			if entry.OID.String() == blobPath.sha && entry.Path == blobPath.path && entry.Change == gitaccess.Delete {
				found = true
			}
		}
		require.True(t, found, "did not find delete for %s %s", blobPath.sha, blobPath.path)
	}

	// These are just a oid/paths to spot check
	blobPaths = []struct {
		sha  string
		path string
	}{
		{"d70f74517561223ca19aade925134cc930d93649", "README.md"},
		{"6e98d2c2bdbdd9c3f8903b9cb276fb9a758396d1", ".gitignore"},
		{"cdfc330a7cbfc5f85031349135e6095cf2266c84", "hack/chains/default-pipelines-demo.sh"},
		{"980ce1d8fc4887774397d3879a413b73459be49a", "openshift-gitops/subscription-openshift-gitops.yaml"},
	}

	for _, blobPath := range blobPaths {
		found := false
		for _, entry := range diff[headRepo] {
			if entry.OID.String() == blobPath.sha && entry.Path == blobPath.path && entry.Change == gitaccess.Add {
				found = true
			}
		}
		require.True(t, found, "did not find add for %s %s", blobPath.sha, blobPath.path)
	}

	// every path in baseRepo should be a delete
	for _, entry := range diff[baseRepo] {
		require.Equal(t, gitaccess.Delete, entry.Change)
	}

	// every path in headRepo should be an add
	for _, entry := range diff[headRepo] {
		require.Equal(t, gitaccess.Add, entry.Change)
	}
}

// Take the output of git ls-tree -r and parse it into a spokes tree.
func treeFromLsTree(t *testing.T, lsTree string) []*spokes.TreeEntry {
	t.Helper()

	entries := []*spokes.TreeEntry{}

	lines := strings.Split(lsTree, "\n")
	for _, line := range lines {
		// last line is empty
		if line == "" {
			continue
		}

		var mode uint32
		var obj string
		var sha string
		var path string
		n, err := fmt.Sscanf(line, `%d %s %s	%s`, &mode, &obj, &sha, &path)
		require.NoError(t, err)
		require.Equal(t, 4, n, "unsuccessful parse")
		require.Equal(t, "blob", obj, "non-blob types not supported yet")

		entry := &spokes.TreeEntry{
			Mode:   &spokes.Mode{Mode: mode},
			Object: spokes.NewBlobObject(&spokes.ObjectID{Id: sha}, 0),
			Path:   &spokes.Path{Name: []byte(path)},
		}
		entries = append(entries, entry)
	}

	return entries
}

package resource

import (
	"context"
	"testing"
	"time"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/keys"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	"github.com/github/migrations-vnext/internal/pkg/set"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func Test_pullRequest_transform(t *testing.T) {
	k, err := keys.ToPullRequestKey("https://github.com/guacamole-bowl/vim/pull/2")
	require.NoError(t, err)

	p := pullRequest{
		pb: &v1.PullRequest{
			Body:                  "replace this attachmentURL with the new one and https://github.com with the new base URL",
			AttachmentResourceIds: []string{"attachmentURL"},
		},
		key: k,
	}

	transformedIDs := resolvedIDsByResource{
		"attachmentURL":      {strVal: "newAttachmentURL"},
		"https://github.com": {strVal: "https://github.localhost"},
	}

	err = p.transform(transformedIDs)
	require.NoError(t, err)

	require.Equal(t,
		"replace this newAttachmentURL with the new one and https://github.localhost with the new base URL",
		p.pb.Body)
}

func createPullRequest(t *testing.T) *v1.PullRequest {
	t.Helper()

	someTine := time.Date(2023, 1, 1, 0, 0, 0, 0, time.UTC)

	return &v1.PullRequest{
		ResourceId:            "http://github.test/test-org/test-repo/pull/2",
		UserResourceId:        "http://github.test/monalisa",
		AssigneesResourceIds:  []string{"http://github.test/mona"},
		ReviewersResourceIds:  []string{"http://github.test/lisa"},
		AttachmentResourceIds: []string{"http://github.test/attachment/1"},
		Title:                 "title",
		Body:                  "body",
		IsDraft:               false,
		BaseRef: &v1.RefDetails{
			Name:      "base",
			CommitSha: "base-sha",
		},
		HeadRef: &v1.RefDetails{
			Name:      "head",
			CommitSha: "head-sha",
		},
		MergeCommitSha: "merge-sha",
		CreatedAt:      timestamppb.New(someTine),
		MergedAt:       timestamppb.New(someTine.Add(time.Second)),
		ClosedAt:       timestamppb.New(someTine.Add(2 * time.Second)),
	}
}

func Test_pullRequest_dependencies(t *testing.T) {
	logger := log.NewNullLogger()

	p := createPullRequest(t)
	pr := newPullRequest(p, logger)
	deps, err := pr.dependencies()
	require.NoError(t, err)

	assert.Equal(t, &transformedDeps{
		int64Deps: set.FromSlice([]string{"http://github.test/test-org/test-repo"}),
		strDeps: set.FromSlice([]string{
			"http://github.test/monalisa",
			"http://github.test/mona",
			"http://github.test/lisa",
			"http://github.test/attachment/1",
			"http://github.test",
		}),
	}, deps)
}

func Test_pullRequest_load(t *testing.T) {
	logger := log.NewNullLogger()

	p := createPullRequest(t)
	pr := newPullRequest(p, logger)

	k, err := keys.ToPullRequestKey(pr.pb.ResourceId)
	require.NoError(t, err)
	pr.key = k

	importer := client.NewDummyImporter(logger)

	resolved := resolvedIDsByResource{
		"http://github.test/test-org/test-repo": {int64Val: 1},
		"http://github.test/monalisa":           {strVal: "monalisa"},
		"http://github.test":                    {strVal: "http://github.com"},
		"http://github.test/mona":               {strVal: "mona"},
		"http://github.test/lisa":               {strVal: "lisa"},
	}

	err = pr.load(context.Background(), importer, resolved)
	require.NoError(t, err)

	expected := &octov1.ImportPullRequestRequest{
		AuthorLogin:      "monalisa",
		RepositoryId:     1,
		BaseRefName:      "base",
		HeadRefName:      "head",
		Title:            "title",
		Body:             "body",
		IsDraft:          false,
		Number:           2,
		MergedAt:         p.MergedAt,
		CreatedAt:        p.CreatedAt,
		ClosedAt:         p.ClosedAt,
		BaseRefCommitSha: "base-sha",
		HeadRefCommitSha: "head-sha",
		Reviewers:        []string{"lisa"},
		Assignees:        []string{"mona"},
		MergeCommitSha:   "merge-sha",
	}

	require.Len(t, importer.PullRequests, 1)
	assert.Equal(t, expected, importer.PullRequests[0])
}

package archive

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

func TestAttachmentResourceExtraction(t *testing.T) {
	type testCase struct {
		a        *Attachment
		expected string
	}
	cases := map[string]*testCase{
		"ExtractsIssue": {
			a: &Attachment{
				Issue: "issue",
			},
			expected: "issue",
		},
		"ExtractsIssueComment": {
			a: &Attachment{
				IssueComment: "issuecomment",
			},
			expected: "issuecomment",
		},
		"ExtractsPullRequest": {
			a: &Attachment{
				PullRequest: "pullrequest",
			},
			expected: "pullrequest",
		},
		"ExtractsPullRequestComment": {
			a: &Attachment{
				PullRequestComment: "pullrequestcomment",
			},
			expected: "pullrequestcomment",
		},
		"ExtractsCommitComment": {
			a: &Attachment{
				CommitComment: "commitcomment",
			},
			expected: "commitcomment",
		},
		"ExtractsDiscussion": {
			a: &Attachment{
				Discussion: "discussion",
			},
			expected: "discussion",
		},
		"ExtractsDiscussionComment": {
			a: &Attachment{
				DiscussionComment: "discussioncomment",
			},
			expected: "discussioncomment",
		},
		"ExtractsFirstAvailable": {
			a: &Attachment{
				Issue:        "issue",
				IssueComment: "issuecomment",
			},
			expected: "issue",
		},
		"ExtractsEmpty": {
			a:        &Attachment{},
			expected: "",
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			assert.Equal(t, tc.expected, tc.a.extractResource())
		})
	}
}

func TestAttachmentExtractRepositoryID(t *testing.T) {
	type testCase struct {
		a        *Attachment
		expected string
		err      bool
	}
	cases := map[string]*testCase{
		"ExtractsErrFromEmpty": {
			a:        &Attachment{},
			expected: "",
			err:      true,
		},
		"ExtractsFromIssue": {
			a: &Attachment{
				Issue: "http://github.test/test-org/test-repo/issues/12",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
		"ExtractsFromIssueComment": {
			a: &Attachment{
				IssueComment: "http://github.test/test-org/test-repo/issues/12#issuecomment-1230213",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
		"ExtractsFromPRIssueComment": {
			a: &Attachment{
				PullRequestComment: "http://github.test/test-org/test-repo/pulls/13#issuecomment-1230213",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
		"ExtractsFromPullRequest": {
			a: &Attachment{
				PullRequest: "http://github.test/test-org/test-repo/pulls/13",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
		"ExtractsFromCommitComment": {
			a: &Attachment{
				CommitComment: "http://github.test/test-org/test-repo/commit/8e950bc74aafc1105236fc2b36322754aac5d725#commitcomment-349",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
		"ExtractsFromDiscussion": {
			a: &Attachment{
				Discussion: "http://github.test/test-org/test-repo/discussions/4116",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
		"ExtractsFromDiscussionComment": {
			a: &Attachment{
				DiscussionComment: "http://github.test/test-org/test-repo/discussions/4116#discussioncomment-1238912389",
			},
			expected: "http://github.test/test-org/test-repo",
			err:      false,
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			repoID, err := tc.a.extractRepositoryResourceID()
			require.Equal(t, tc.err, err != nil)
			require.Equal(t, tc.expected, repoID)
		})
	}
}

func TestAttachmentConversion(t *testing.T) {
	someTime := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	resourceID := "http://alambic.github.test/storage/user/123/files/someid"
	assetURL := "tarball://root/attachments/someid/whatever.png"
	referencedByResource := "http://github.test/test-org/test-repo/issues/12"
	a := &Attachment{
		Type:             "attachment",
		URL:              resourceID,
		User:             "http://github.test/monalisa",
		AssetName:        "whatever.png",
		AssetContentType: "image/png",
		AssetURL:         assetURL,
		CreatedAt:        someTime,
		Issue:            referencedByResource,
	}

	expected := &v1.Attachment{
		ResourceId:           resourceID,
		Type:                 "attachment",
		RepositoryId:         "http://github.test/test-org/test-repo",
		Name:                 "whatever.png",
		ContentType:          "image/png",
		UserResourceId:       "http://github.test/monalisa",
		AssetUrl:             assetURL,
		ReferencedByResource: referencedByResource,
	}
	v1a, err := a.ToV1Attachment()
	require.NoError(t, err)
	require.Equal(t, expected, v1a)
}

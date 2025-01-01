package archive

import (
	"testing"
	"time"

	"github.com/github/migrations-vnext/internal/pkg/keys"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIssueEventConversion(t *testing.T) {
	createdAt := time.Date(2024, time.October, 8, 10, 0, 0, 0, time.UTC)
	ie := &IssueEvent{
		URL:                    "http://github.test/test-repo/test-org/issues/2#event-1234",
		Issue:                  "http://github.test/test-repo/test-org/issues/2",
		Actor:                  "http://github.test/monalisa",
		Subject:                "http://github.test/monalisa2",
		Event:                  "subscribed",
		CreatedAt:              createdAt,
		LabelName:              "label-foo",
		TitleIs:                "title-foo",
		TitleWas:               "title-bar",
		MilestoneTitle:         "milestone-foo",
		ColumnName:             "col-foo",
		PreviousColumnName:     "col-bar",
		LockReason:             "universelol",
		BlockDurationDays:      1,
		Message:                "msg",
		ReferencingPullRequest: "http://github.test/test-repo/test-org/pulls/7",
		CommitID:               "commit-id",
		CommitRepository:       "http://github.test/test-repo/test-org",
		BeforeCommitOID:        "before-commit-oid",
		AfterCommitOID:         "after-commit-oid",
		Ref:                    "ref",
	}
	expected := &v1.IssueEvent{
		ResourceId:                       ie.URL,
		ActorResourceId:                  ie.Actor,
		SubjectUserResourceId:            ie.Subject,
		SubjectIssueResourceId:           "", // Explicitly empty.
		Event:                            ie.Event,
		CreatedAt:                        toTimestamp(createdAt),
		LabelName:                        ie.LabelName,
		TitleIs:                          ie.TitleIs,
		TitleWas:                         ie.TitleWas,
		MilestoneTitle:                   ie.MilestoneTitle,
		ColumnName:                       ie.ColumnName,
		PreviousColumnName:               ie.PreviousColumnName,
		LockReason:                       ie.LockReason,
		BlockDurationDays:                ie.BlockDurationDays,
		Message:                          ie.Message,
		ReferencingPullRequestResourceId: ie.ReferencingPullRequest,
		CommitRepositoryResourceId:       ie.CommitRepository,
		CommitId:                         ie.CommitID,
		BeforeCommitOid:                  ie.BeforeCommitOID,
		AfterCommitOid:                   ie.AfterCommitOID,
		Ref:                              ie.Ref,
	}
	v1ie, err := ie.ToV1IssueEvent()
	require.NoError(t, err)
	require.Equal(t, expected, v1ie)

	// Change the subject to an issue to make sure it's extracted correctly.
	ie.Subject = "http://github.test/test-repo/test-repo/issues/7"
	expected.SubjectUserResourceId = ""
	expected.SubjectIssueResourceId = ie.Subject
	v1ie, err = ie.ToV1IssueEvent()
	require.NoError(t, err)
	require.Equal(t, expected, v1ie)
}

func TestIsIssueEvent(t *testing.T) {
	type testCase struct {
		ie       *IssueEvent
		expected bool
	}
	cases := map[string]*testCase{
		"PRReference": {
			ie: &IssueEvent{
				Issue:                  "",
				ReferencingPullRequest: "notempty",
			},
			expected: false,
		},
		"IssueReference": {
			ie: &IssueEvent{
				Issue:                  "notempty",
				ReferencingPullRequest: "",
			},
			expected: true,
		},
		"ProjectNotSupported": {
			ie: &IssueEvent{
				Issue:                  "notmpety",
				Event:                  "added_to_project",
				ReferencingPullRequest: "",
			},
			expected: false,
		},
		"ReferencingPullRequestNotSupported": {
			ie: &IssueEvent{
				Issue:                  "notmpety",
				ReferencingPullRequest: "notempty",
			},
			expected: false,
		},
		"MentionedWithoutActorNotSupported": {
			ie: &IssueEvent{
				Issue: "notempty",
				Event: "mentioned",
			},
			expected: false,
		},
		"AddedToProjectNotSupported": {
			ie: &IssueEvent{
				Issue: "notempty",
				Event: "added_to_project",
			},
			expected: false,
		},
		"MovedColumnsNotSupported": {
			ie: &IssueEvent{
				Issue: "notempty",
				Event: "moved_columns_in_project",
			},
			expected: false,
		},
		"RemovedFromProjectNotSupported": {
			ie: &IssueEvent{
				Issue: "notempty",
				Event: "removed_from_project",
			},
		},
		"ConvertedNoteToIssueNotSupported": {
			ie: &IssueEvent{
				Issue: "notempty",
				Event: "converted_note_to_issue",
			},
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			res := tc.ie.IsSupported()
			require.Equal(t, tc.expected, res)
		})
	}
}

func Test_isSameRepoKeys(t *testing.T) {
	type args struct {
		a []keys.RepositoryKey
		b []keys.RepositoryKey
	}
	tests := []struct {
		name string
		args args
		want bool
	}{
		{
			name: "returns true a and b are the same set",
			args: args{
				a: []keys.RepositoryKey{
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo1",
					},
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo2",
					},
				},
				b: []keys.RepositoryKey{
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo2",
					},
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo1",
					},
				},
			},
			want: true,
		},
		{
			name: "returns false if a is not a subset of b",
			args: args{
				a: []keys.RepositoryKey{
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo1",
					},
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo2",
					},
				},
				b: []keys.RepositoryKey{
					{
						OrganizationKey: keys.OrganizationKey{
							Scheme:         keys.SchemeHTTP,
							EnterpriseName: "github.com",
							OrgLogin:       "org1",
						},
						Name: "repo3",
					},
				},
			},
			want: false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equalf(t, tt.want, isSameRepoKeys(tt.args.a, tt.args.b), "isSameRepoKeys(%v, %v)", tt.args.a, tt.args.b)
		})
	}
}

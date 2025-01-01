package keys

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestToOrganizationKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    OrganizationKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name:    "parses organization key",
			args:    args{s: "http://github.dev/guacamole-bowl"},
			want:    OrganizationKey{Scheme: SchemeHTTP, EnterpriseName: "github.dev", OrgLogin: "guacamole-bowl"},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToOrganizationKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToOrganizationKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToOrganizationKey(%v)", tt.args.s)
		})
	}
}

func TestToTeamKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    TeamKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses team key",
			args: args{s: "http://github.dev/orgs/guacamole-bowl/teams/a-team"},
			want: TeamKey{
				OrganizationKey: OrganizationKey{Scheme: SchemeHTTP, EnterpriseName: "github.dev", OrgLogin: "guacamole-bowl"},
				TeamLogin:       "a-team",
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToTeamKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToTeamKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToTeamKey(%v)", tt.args.s)
		})
	}
}

func TestToMannequinKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    MannequinKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name:    "parses mannequin key",
			args:    args{s: "http://github.dev/monalisa"},
			want:    MannequinKey{Scheme: SchemeHTTP, EnterpriseName: "github.dev", UserLogin: "monalisa"},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToMannequinKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToMannequinKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToMannequinKey(%v)", tt.args.s)
		})
	}
}

func TestToRepositoryKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    RepositoryKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses repository key",
			args: args{s: "http://github.dev/guacamole-bowl/vim"},
			want: RepositoryKey{
				OrganizationKey: OrganizationKey{
					Scheme:         SchemeHTTP,
					EnterpriseName: "github.dev",
					OrgLogin:       "guacamole-bowl"},
				Name: "vim",
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToRepositoryKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToRepositoryKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToRepositoryKey(%v)", tt.args.s)
		})
	}
}

func TestToIssueKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    IssueKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses issue key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/issues/2"},
			want: IssueKey{
				RepositoryKey: RepositoryKey{
					OrganizationKey: OrganizationKey{
						Scheme:         SchemeHTTP,
						EnterpriseName: "github.dev",
						OrgLogin:       "guacamole-bowl",
					},
					Name: "vim",
				},
				Number: 2,
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToIssueKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToIssueKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToIssueKey(%v)", tt.args.s)
		})
	}
}

func TestToIssueCommentKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    IssueCommentKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses issue comment key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/issues/2#issuecomment-3"},
			want: IssueCommentKey{
				IssueKey: IssueKey{
					RepositoryKey: RepositoryKey{
						OrganizationKey: OrganizationKey{
							Scheme:         SchemeHTTP,
							EnterpriseName: "github.dev",
							OrgLogin:       "guacamole-bowl",
						},
						Name: "vim"},
					Number: 2,
				},
				CommentID: 3},
			wantErr: assert.NoError,
		},
		{
			name: "parses pull request comment key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/pull/2#issuecomment-3"},
			want: IssueCommentKey{
				IssueKey: IssueKey{
					RepositoryKey: RepositoryKey{
						OrganizationKey: OrganizationKey{
							Scheme:         SchemeHTTP,
							EnterpriseName: "github.dev",
							OrgLogin:       "guacamole-bowl",
						},
						Name: "vim"},
					Number:        2,
					IsPullRequest: true,
				},
				CommentID: 3},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToIssueCommentKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToIssueCommentKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToIssueCommentKey(%v)", tt.args.s)
		})
	}
}

func TestToIssueEventKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    IssueEventKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses issue event key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/issues/2#event-3"},
			want: IssueEventKey{
				IssueKey: IssueKey{
					RepositoryKey: RepositoryKey{
						OrganizationKey: OrganizationKey{
							Scheme:         SchemeHTTP,
							EnterpriseName: "github.dev",
							OrgLogin:       "guacamole-bowl",
						},
						Name: "vim"},
					Number: 2,
				},
				EventID: 3},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToIssueEventKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToIssueEventKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToIssueEventKey(%v)", tt.args.s)
		})
	}
}

func TestToPRKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    PullRequestKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses PR key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/pull/2"},
			want: PullRequestKey{
				RepositoryKey: RepositoryKey{
					OrganizationKey: OrganizationKey{
						Scheme:         SchemeHTTP,
						EnterpriseName: "github.dev",
						OrgLogin:       "guacamole-bowl",
					},
					Name: "vim",
				},
				Number:        2,
				IsPullRequest: true,
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToPullRequestKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToPullRequestKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToPullRequestKey(%v)", tt.args.s)
		})
	}
}

func TestToPRReviewKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    PullRequestReviewKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses PR review key with archive format",
			args: args{s: "http://github.dev/guacamole-bowl/vim/pull/2/files#pullrequestreview-3"},
			want: PullRequestReviewKey{
				PullRequestKey: PullRequestKey{
					RepositoryKey: RepositoryKey{
						OrganizationKey: OrganizationKey{
							Scheme:         SchemeHTTP,
							EnterpriseName: "github.dev",
							OrgLogin:       "guacamole-bowl",
						},
						Name: "vim",
					},
					Number:        2,
					IsPullRequest: true,
				},
				ReviewID: 3,
			},
			wantErr: assert.NoError,
		},
		{
			name: "parses PR review key with crawler format",
			args: args{s: "http://github.dev/guacamole-bowl/vim/pull/2#pullrequestreview-3"},
			want: PullRequestReviewKey{
				PullRequestKey: PullRequestKey{
					RepositoryKey: RepositoryKey{
						OrganizationKey: OrganizationKey{
							Scheme:         SchemeHTTP,
							EnterpriseName: "github.dev",
							OrgLogin:       "guacamole-bowl",
						},
						Name: "vim",
					},
					Number:        2,
					IsPullRequest: true,
				},
				ReviewID:      3,
				CrawlerFormat: true,
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToPullRequestReviewKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToPullRequestKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToPullRequestKey(%v)", tt.args.s)
		})
	}
}

func TestToMilestoneKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    MilestoneKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses milestone key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/milestones/1"},
			want: MilestoneKey{
				RepositoryKey: RepositoryKey{
					OrganizationKey: OrganizationKey{
						Scheme:         SchemeHTTP,
						EnterpriseName: "github.dev",
						OrgLogin:       "guacamole-bowl",
					},
					Name: "vim",
				},
				MilestoneID: 1,
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToMilestoneKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToMilestoneKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToMilestoneKey(%v)", tt.args.s)
		})
	}
}

func TestToCommitCommentKey(t *testing.T) {
	type args struct {
		s string
	}
	tests := []struct {
		name    string
		args    args
		want    CommitCommentKey
		wantErr assert.ErrorAssertionFunc
	}{
		{
			name: "parses commit comment key",
			args: args{s: "http://github.dev/guacamole-bowl/vim/commit/8e950bc74aafc1105236fc2b36322754aac5d725#commitcomment-3"},
			want: CommitCommentKey{
				RepositoryKey: RepositoryKey{
					OrganizationKey: OrganizationKey{
						Scheme:         SchemeHTTP,
						EnterpriseName: "github.dev",
						OrgLogin:       "guacamole-bowl",
					},
					Name: "vim"},
				CommitID:  "8e950bc74aafc1105236fc2b36322754aac5d725",
				CommentID: 3,
			},
			wantErr: assert.NoError,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ToCommitCommentKey(tt.args.s)
			if !tt.wantErr(t, err, fmt.Sprintf("ToCommitCommentKey(%v)", tt.args.s)) {
				return
			}
			assert.Equalf(t, tt.want, got, "ToCommitCommentKey(%v)", tt.args.s)
		})
	}
}

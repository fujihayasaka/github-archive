package archive

import (
	"fmt"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// ProtectedBranch represents a set of protected branch settings.
type ProtectedBranch struct {
	Type                                 string   `json:"type"`
	Name                                 string   `json:"name"`
	URL                                  string   `json:"url"`
	CreatorURL                           string   `json:"creator_url"`
	RepositoryURL                        string   `json:"repository_url"`
	AdminEnforced                        bool     `json:"admin_enforced"`
	BlockDeletionsEnforcementLevel       int32    `json:"block_deletions_enforcement_level"`
	BlockForcePushesEnforcementLevel     int32    `json:"block_force_pushes_enforcement_level"`
	DismissStaleReviewsOnPush            bool     `json:"dismiss_stale_reviews_on_push"`
	PullRequestReviewsEnforcementLevel   string   `json:"pull_request_reviews_enforcement_level"`
	RequireCodeOwnerReview               bool     `json:"require_code_owner_review"`
	RequiredStatusChecksEnforcementLevel string   `json:"required_status_checks_enforcement_level"`
	StrictRequiredStatusChecksPolicy     bool     `json:"strict_required_status_checks_policy"`
	AuthorizedActorsOnly                 bool     `json:"authorized_actors_only"`
	AuthorizedUserURLs                   []string `json:"authorized_user_urls"`
	AuthorizedTeamURLs                   []string `json:"authorized_team_urls"`
	DismissalRestrictedUserURLs          []string `json:"dismissal_restricted_user_urls"`
	DismissalRestrictedTeamURLs          []string `json:"dismissal_restricted_team_urls"`
	RequiresStatusChecks                 bool     `json:"requires_status_checks"`
	RequiredStatusChecks                 []string `json:"required_status_checks"`
	RequiresApprovingReviews             bool     `json:"requires_approving_reviews"`
	RequiredApprovingReviewCount         int32    `json:"required_approving_review_count"`
	RequiresLinearHistory                bool     `json:"requires_linear_history"`
	AllowsForcePushes                    bool     `json:"allows_force_pushes"`
	AllowsDeletions                      bool     `json:"allows_deletions"`
	RestrictsReviewDismissals            bool     `json:"restricts_review_dismissals"`
	RequiresReviewThreadResolution       bool     `json:"requires_review_thread_resolution"`
	RequiresCommitSignatures             bool     `json:"requires_commit_signatures"`
	RequireLastPushApproval              bool     `json:"require_last_push_approval"`
}

// ToV1ProtectedBranch converts a ProtectedBranch to a v1.ProtectedBranch.
func (p *ProtectedBranch) ToV1ProtectedBranch() (*v1.ProtectedBranch, error) {
	return &v1.ProtectedBranch{
		ResourceId:           fmt.Sprintf("protectedbranch-%s-%s", p.Name, p.RepositoryURL),
		RepositoryResourceId: p.RepositoryURL,
		Name:                 p.Name,
		RequiresApprovingReviews: &wrapperspb.BoolValue{
			Value: p.RequiresApprovingReviews,
		},
		RequiredApprovingReviewCount: &wrapperspb.Int32Value{
			Value: p.RequiredApprovingReviewCount,
		},
		RequiresCommitSignatures: &wrapperspb.BoolValue{
			Value: p.RequiresCommitSignatures,
		},
		RequiresLinearHistory: &wrapperspb.BoolValue{
			Value: p.RequiresLinearHistory,
		},
		AllowsForcePushes: &wrapperspb.BoolValue{
			Value: p.AllowsForcePushes,
		},
		AllowsDeletions: &wrapperspb.BoolValue{
			Value: p.AllowsDeletions,
		},
		IsAdminEnforced: &wrapperspb.BoolValue{
			Value: p.AdminEnforced,
		},
		RequiresStatusChecks: &wrapperspb.BoolValue{
			Value: p.RequiresStatusChecks,
		},
		RequiresStrictStatusChecks: &wrapperspb.BoolValue{
			Value: p.StrictRequiredStatusChecksPolicy,
		},
		RequiresCodeOwnerReviews: &wrapperspb.BoolValue{
			Value: p.RequireCodeOwnerReview,
		},
		DismissesStaleReviews: &wrapperspb.BoolValue{
			Value: p.DismissStaleReviewsOnPush,
		},
		RestrictsReviewDismissals: &wrapperspb.BoolValue{
			Value: p.RestrictsReviewDismissals,
		},
		RestrictsPushes: &wrapperspb.BoolValue{
			Value: p.AuthorizedActorsOnly,
		},
		RequiredStatusCheckContexts: p.RequiredStatusChecks,
		RequiresReviewThreadResolution: &wrapperspb.BoolValue{
			Value: p.RequiresReviewThreadResolution,
		},
		RequireLastPushApproval: &wrapperspb.BoolValue{
			Value: p.RequireLastPushApproval,
		},
	}, nil
}

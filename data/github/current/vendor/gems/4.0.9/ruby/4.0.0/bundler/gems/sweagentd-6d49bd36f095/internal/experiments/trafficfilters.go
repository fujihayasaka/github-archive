package experiments

import (
	"context"
	"net/http"

	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
)

// TrafficFilterHeader represents the headers pre-registered with ExP for use
// as traffic filters.
type TrafficFilterHeader string

const (
	// GitHubPullRequestIDHeader and related constants define traffic filter headers
	// that are pre-registered with ExP for experiment traffic filtering.
	GitHubPullRequestIDHeader TrafficFilterHeader = "X-GitHub-PullRequestId"
	// CopilotRepositoryHeader is used to filter experiments by repository.
	CopilotRepositoryHeader TrafficFilterHeader = "X-Copilot-Repository"
	// CopilotOrgsHeader is used to filter experiments by organization.
	CopilotOrgsHeader TrafficFilterHeader = "X-Copilot-Orgs"
	// CopilotTrackingIDHeader is used to filter experiments by user tracking ID.
	CopilotTrackingIDHeader TrafficFilterHeader = "X-GitHub-CopilotTrackingID"
	// UserKindHeader is used to filter experiments by user kind (GitHub, Microsoft, etc.).
	UserKindHeader TrafficFilterHeader = "X-Copilot-UserKind"
	// RepoVisibilityHeader is used to filter experiments by repository visibility.
	RepoVisibilityHeader TrafficFilterHeader = "X-Copilot-RepositoryVisibility"
)

// String returns the string representation of the TrafficFilterHeader.
func (h TrafficFilterHeader) String() string {
	return string(h)
}

// TrafficFilter represents a single traffic filter with a header and value.
type TrafficFilter struct {
	Header TrafficFilterHeader
	Value  string
}

// TrafficFilters implements the TrafficFilterManager interface.
type TrafficFilters []*TrafficFilter

// Traffic Filter Factory Functions
// These factory functions create new TrafficFilter instances for common ExP filters.
// Use these when composing custom TrafficFilters for experiments.

// NewRepositoryFilter creates a new TrafficFilter for filtering by repository.
func NewRepositoryFilter() *TrafficFilter {
	return &TrafficFilter{
		Header: CopilotRepositoryHeader,
		Value:  "",
	}
}

// NewOrgsFilter creates a new TrafficFilter for filtering by organization.
func NewOrgsFilter() *TrafficFilter {
	return &TrafficFilter{
		Header: CopilotOrgsHeader,
		Value:  "",
	}
}

// NewUserKindFilter creates a new TrafficFilter for filtering by membership in a GitHub or Microsoft organization.
func NewUserKindFilter() *TrafficFilter {
	return &TrafficFilter{
		Header: UserKindHeader,
		Value:  "",
	}
}

// NewRepositoryVisibilityFilter creates a new TrafficFilter for filtering by repository visibility (public/private/internal).
func NewRepositoryVisibilityFilter() *TrafficFilter {
	return &TrafficFilter{
		Header: RepoVisibilityHeader,
		Value:  "",
	}
}

// Set updates or add a TrafficFilter in the TrafficFilters slice.
// If a filter with the same header already exists, it updates its value.
func (tf *TrafficFilters) Set(trafficFilter *TrafficFilter) {
	for _, filter := range *tf {
		if filter.Header == trafficFilter.Header {
			filter.Value = trafficFilter.Value
			return
		}
	}
	*tf = append(*tf, trafficFilter)
}

// SetHTTPHeaders sets the HTTP headers for the request based on the TrafficFilters.
// This is used to apply the traffic filters to outgoing requests.
func (tf *TrafficFilters) SetHTTPHeaders(req *http.Request) {
	for _, filter := range *tf {
		if filter.Header.String() != "" && filter.Value != "" {
			req.Header.Set(filter.Header.String(), filter.Value)
		}
	}
}

// Organization AnalyticTrackingIDs for UserKind checks
const (
	ghOrgID        string = "4535c7beffc844b46bb1ed4aa04d759a" // https://admin.github.com/stafftools/users/github
	msCopilotOrgID string = "7184f66dfcee98cb5f08a1cb936d5225" // https://admin.github.com/stafftools/users/ms-copilot
	msOrgID        string = "a5db0bcaae94032fe715fb34a5e4bce2" // https://admin.github.com/stafftools/users/microsoft
	argosGhOrgID   string = "29d68188f12a41b5d95f9806792d9938" // https://admin.github.com/stafftools/users/argos-gh
)

// UserKind holds the user's organization membership status for GitHub, Microsoft, and Microsoft Copilot.
type UserKind struct {
	GitHub           bool
	Microsoft        bool
	MicrosoftCopilot bool
	ArgosGh          bool
}

// Hash returns the hash value for the UserKind based on the organization membership.
// It is hierarchical, so if a user is a member of multiple organizations, they will
// only return the hash for whichever org is at the top of this conditional hierarchy.
// For example, if a user is a member of both GitHub and Microsoft Copilot, they will
// return the hash for GitHub.
func (u *UserKind) Hash() string {
	switch {
	case u.GitHub:
		return ghOrgID
	case u.MicrosoftCopilot:
		return msCopilotOrgID
	case u.Microsoft:
		return msOrgID
	case u.ArgosGh:
		return argosGhOrgID
	default:
		return "unknown"
	}
}

func getUserKind(ctx context.Context, twirpClient githubtwirp.ClientInterface, userID uint64) (*UserKind, error) {
	// Fetch copilot organizations for the specific user from twirp API
	userDetails, err := twirpClient.GetCopilotUserDetails(ctx, int64(userID))
	if err != nil {
		return nil, goerrors.Errorf("failed to get copilot user %d: %w", userID, err)
	}

	orgs := userDetails.CopilotOrganizations

	userKind := &UserKind{}
	// Check if user is in any staff organizations
	for _, org := range orgs {
		if org.AnalyticsTrackingId != "" {
			orgID := org.AnalyticsTrackingId
			switch orgID {
			case ghOrgID:
				userKind.GitHub = true
			case msOrgID:
				userKind.Microsoft = true
			case msCopilotOrgID:
				userKind.MicrosoftCopilot = true
			case argosGhOrgID:
				userKind.ArgosGh = true
			default:
				// Organization not relevant for user kind determination
			}
		}
		if userKind.GitHub && userKind.Microsoft && userKind.MicrosoftCopilot && userKind.ArgosGh {
			return userKind, nil // All orgs found, no need to check further
		}
	}

	return userKind, nil
}

func getRepositoryVisibility(ctx context.Context, twirpClient githubtwirp.ClientInterface, repoID int64) (string, error) {
	repo, err := twirpClient.GetRepoById(ctx, repoID)
	if err != nil {
		return "", goerrors.Errorf("failed to get repository %d: %w", repoID, err)
	}

	if repo == nil {
		return "", goerrors.Errorf("repository %d not found", repoID)
	}

	switch repo.Visibility {
	case repositoriesTwirp.Visibility_VISIBILITY_PUBLIC:
		return "public", nil
	case repositoriesTwirp.Visibility_VISIBILITY_PRIVATE:
		return "private", nil
	case repositoriesTwirp.Visibility_VISIBILITY_INTERNAL:
		return "internal", nil
	default:
		return "", goerrors.Errorf("unknown repository visibility: %v", repo.Visibility)
	}
}

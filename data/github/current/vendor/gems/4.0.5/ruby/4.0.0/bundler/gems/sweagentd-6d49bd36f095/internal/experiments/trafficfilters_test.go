package experiments

import (
	"context"
	"errors"
	"testing"

	v1 "github.com/github/copilot-twirp/proto/users/v1"
	repositoriesTwirp "github.com/github/github-proto/gen/go/repositories/v1"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TrafficFilters tests

func TestTrafficFiltersSet(t *testing.T) {
	filterToSet := &TrafficFilter{
		Header: TrafficFilterHeader("X-Example-Header"),
		Value:  "example-value",
	}
	tests := []struct {
		name                   string
		tf                     *TrafficFilters
		expectedTrafficFilters *TrafficFilters
	}{
		{
			name:                   "Set with nil TrafficFilter",
			tf:                     &TrafficFilters{},
			expectedTrafficFilters: &TrafficFilters{filterToSet},
		},
		{
			name: "Set with existing TrafficFilter",
			tf: &TrafficFilters{
				&TrafficFilter{
					Header: TrafficFilterHeader("X-Existing-Header"),
					Value:  "existing-value",
				},
			},
			expectedTrafficFilters: &TrafficFilters{
				&TrafficFilter{
					Header: TrafficFilterHeader("X-Existing-Header"),
					Value:  "existing-value",
				},
				filterToSet,
			},
		},
		{
			name: "Change existing TrafficFilter",
			tf: &TrafficFilters{
				&TrafficFilter{
					Header: filterToSet.Header,
					Value:  "existing-value",
				},
			},
			expectedTrafficFilters: &TrafficFilters{
				filterToSet,
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.tf.Set(filterToSet)
			assert.Equal(t, tt.expectedTrafficFilters, tt.tf)
		})
	}
}

func Test_getUserKind(t *testing.T) {
	tests := []struct {
		name     string
		orgs     []*v1.CopilotOrganization
		expected *UserKind
	}{
		{
			name:     "user in GitHub org",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: ghOrgID}},
			expected: &UserKind{GitHub: true},
		},
		{
			name:     "user in Microsoft org",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: msOrgID}},
			expected: &UserKind{Microsoft: true},
		},
		{
			name:     "user in MS Copilot org",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: msCopilotOrgID}},
			expected: &UserKind{MicrosoftCopilot: true},
		},
		{
			name:     "user in ArgosGH org",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: argosGhOrgID}},
			expected: &UserKind{ArgosGh: true},
		},
		{
			name:     "user in unknown org",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: "unknown"}},
			expected: &UserKind{},
		},
		{
			name:     "user in no orgs",
			orgs:     []*v1.CopilotOrganization{},
			expected: &UserKind{},
		},
		{
			name:     "user in multiple orgs including staff org",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: ghOrgID}, {AnalyticsTrackingId: "12345"}},
			expected: &UserKind{GitHub: true},
		},
		{
			name:     "user in all tracked orgs",
			orgs:     []*v1.CopilotOrganization{{AnalyticsTrackingId: ghOrgID}, {AnalyticsTrackingId: msOrgID}, {AnalyticsTrackingId: msCopilotOrgID}, {AnalyticsTrackingId: argosGhOrgID}},
			expected: &UserKind{GitHub: true, Microsoft: true, MicrosoftCopilot: true, ArgosGh: true},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create Twirp client with the test server URL
			twirpClient := &githubtwirp.NoopClient{
				NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
					MockGetCopilotUser: func(ctx context.Context, req *v1.GetCopilotUserRequest) (*v1.GetCopilotUserResponse, error) {
						return &v1.GetCopilotUserResponse{
							UserDetails: &v1.CopilotUserDetails{
								AnalyticsTrackingId:  "test-tracking-id",
								CopilotOrganizations: tt.orgs,
							},
						}, nil
					},
				},
			}

			userKind, err := getUserKind(context.Background(), twirpClient, 12345)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, userKind)
		})
	}
}

func Test_getUserKindAPIError(t *testing.T) {
	// Create GitHub client with the test server URL
	twirpClient := &githubtwirp.NoopClient{
		NoopUserDetailAPI: &githubtwirp.NoopUserDetailAPI{
			MockGetCopilotUser: func(ctx context.Context, req *v1.GetCopilotUserRequest) (*v1.GetCopilotUserResponse, error) {
				return &v1.GetCopilotUserResponse{
					UserDetails: &v1.CopilotUserDetails{
						AnalyticsTrackingId:  "test-tracking-id",
						CopilotOrganizations: nil,
					},
				}, errors.New("failed to list user organizations")
			},
		},
	}

	userKind, err := getUserKind(context.Background(), twirpClient, 12345)
	require.Error(t, err)
	assert.Nil(t, userKind)
	assert.Contains(t, err.Error(), "failed to list user organizations")
}

func Test_UserKindHash(t *testing.T) {
	tests := []struct {
		name     string
		userKind *UserKind
		expected string
	}{
		{
			name:     "GitHub user",
			userKind: &UserKind{GitHub: true},
			expected: ghOrgID,
		},
		{
			name:     "Microsoft Copilot user",
			userKind: &UserKind{MicrosoftCopilot: true},
			expected: msCopilotOrgID,
		},
		{
			name:     "Microsoft user",
			userKind: &UserKind{Microsoft: true},
			expected: msOrgID,
		},
		{
			name:     "Unknown user",
			userKind: &UserKind{},
			expected: "unknown",
		},
		{
			name:     "All orgs user",
			userKind: &UserKind{GitHub: true, Microsoft: true, MicrosoftCopilot: true},
			expected: ghOrgID, // Prioritize GitHub org
		},
		{
			name: "MSCopilot and Microsoft user",
			userKind: &UserKind{
				MicrosoftCopilot: true,
				Microsoft:        true,
			},
			expected: msCopilotOrgID, // Prioritize Microsoft Copilot org
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, tt.userKind.Hash())
		})
	}
}

func Test_getRepositoryVisibility(t *testing.T) {
	tests := []struct {
		name       string
		visibility repositoriesTwirp.Visibility
		expected   string
	}{
		{
			name:       "repo is public",
			visibility: repositoriesTwirp.Visibility_VISIBILITY_PUBLIC,
			expected:   "public",
		},
		{
			name:       "repo is private",
			visibility: repositoriesTwirp.Visibility_VISIBILITY_PRIVATE,
			expected:   "private",
		},
		{
			name:       "repo is internal",
			visibility: repositoriesTwirp.Visibility_VISIBILITY_INTERNAL,
			expected:   "internal",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create Twirp client with mock response
			twirpClient := githubtwirp.NewNoopClient()
			twirpClient.NoopRepositoriesAPI.MockFindRepositories = func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
				return &repositoriesTwirp.FindRepositoriesResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{
						{
							Id:         12345,
							Visibility: tt.visibility,
						},
					},
				}, nil
			}

			visibility, err := getRepositoryVisibility(context.Background(), twirpClient, 12345)
			require.NoError(t, err)
			assert.Equal(t, tt.expected, visibility)
		})
	}
}

func Test_getRepositoryVisibilityAPIError(t *testing.T) {
	tests := []struct {
		name               string
		mockFunc           func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error)
		expectedVisibility string
		expectedError      string
	}{
		{
			name: "api returns error",
			mockFunc: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
				return nil, errors.New("failed to get repository")
			},
			expectedVisibility: "",
			expectedError:      "failed to get repository 12345: failed to get repository",
		},
		{
			name: "api returns empty repositories",
			mockFunc: func(ctx context.Context, req *repositoriesTwirp.FindRepositoriesRequest) (*repositoriesTwirp.FindRepositoriesResponse, error) {
				return &repositoriesTwirp.FindRepositoriesResponse{
					Repositories: []*repositoriesTwirp.RepositoryListItem{},
				}, nil
			},
			expectedVisibility: "",
			expectedError:      "failed to get repository 12345",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Create Twirp client with mock function
			twirpClient := githubtwirp.NewNoopClient()
			twirpClient.NoopRepositoriesAPI.MockFindRepositories = tt.mockFunc

			visibility, err := getRepositoryVisibility(context.Background(), twirpClient, 12345)
			require.Error(t, err)
			assert.Equal(t, tt.expectedVisibility, visibility)
			assert.Contains(t, err.Error(), tt.expectedError)
		})
	}
}

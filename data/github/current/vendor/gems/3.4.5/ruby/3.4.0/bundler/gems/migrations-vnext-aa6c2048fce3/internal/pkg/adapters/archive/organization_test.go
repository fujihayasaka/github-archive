package archive

import (
	"testing"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

func TestOrganizationConversion(t *testing.T) {
	o := &Organization{
		URL:   "http://github.test/test-org",
		Login: "test-org",
		Name:  "Test Org",
	}

	expected := &v1.Organization{
		ResourceId: o.URL,
		Name:       o.Name,
		Login:      o.Login,
	}

	v1o, err := o.ToV1Organization()
	require.NoError(t, err)
	require.Equal(t, expected, v1o)
}

func strPtr(s string) *string {
	return &s
}

func TestToOrganizationSettings(t *testing.T) {
	// Initialize the Organization object
	org := &Organization{
		URL:         "http://github.test/test-org",
		Login:       "test-org",
		Name:        "Test Organization",
		Description: "This is a test organization.",
		Website:     "https://test.org",
		Location:    "Test Location",
		Email:       "test@test.org",
		Members: []Member{
			{
				User:  "user1",
				Role:  "admin",
				State: "active",
			},
		},
		OwnersTeam: "owners-team",
		Webhooks: []*Webhook{
			{
				PayloadURL:            "http://example.com/webhook",
				ContentType:           "json",
				EventTypes:            []string{"push", "pull_request"},
				EnableSSLVerification: true,
				Active:                true,
			},
		},
		CreatedAt: time.Now(),
		MemberPrivileges: &MemberPrivileges{
			DefaultRepositoryPermission:            strPtr("write"),
			MembersCanCreatePublicRepositories:     boolPtr(true),
			MembersCanCreatePrivateRepositories:    boolPtr(false),
			MembersCanCreateInternalRepositories:   boolPtr(true),
			MembersCanInviteOutsideCollaborators:   boolPtr(false),
			AllowsPrivateRepositoryForking:         boolPtr(true),
			MembersCanCreatePages:                  boolPtr(true),
			MembersCanChangeRepoVisibility:         boolPtr(false),
			MembersCanDeleteRepositories:           boolPtr(true),
			MembersCanDeleteIssues:                 boolPtr(false),
			DisplayCommenterFullNameSettingEnabled: boolPtr(true),
			ReadersCanCreateDiscussions:            boolPtr(false),
			MembersCanCreateTeams:                  boolPtr(true),
			MembersCanViewDependencyInsights:       boolPtr(true),
		},
		RepositoryDefaults: &RepositoryDefaults{
			RepositoryDefaultBranch: strPtr("main"),
			CommitSignoff:           boolPtr(true),
			RepositoryLabels: []Label{
				{
					Name:        "bug",
					Description: "A bug label",
					Color:       "f29513",
					Default:     true,
				},
			},
		},
		// these labels are not included in organization settings currently.
		Labels: []Label{
			{
				Name:        "enhancement",
				Description: "An enhancement label",
				Color:       "a2eeef",
				Default:     false,
			},
		},
	}

	v1OrgSettings := org.ToV1InitialOrganizationSettings()

	expectedRepoLabels := []*v1.Label{
		{
			Name:        "bug",
			Color:       "f29513",
			Default:     true,
			Description: "A bug label",
		},
	}

	expectedWebhooks := []*v1.Webhook{
		{
			PayloadUrl:            "http://example.com/webhook",
			ContentType:           "json",
			EventTypes:            []string{"push", "pull_request"},
			EnableSslVerification: true,
			Active:                true,
		},
	}

	expectedMemberPrivileges := &v1.MemberPrivileges{
		DefaultRepositoryPermission:            &wrapperspb.StringValue{Value: "write"},
		MembersCanCreatePublicRepositories:     &wrapperspb.BoolValue{Value: true},
		MembersCanCreatePrivateRepositories:    &wrapperspb.BoolValue{Value: false},
		MembersCanCreateInternalRepositories:   &wrapperspb.BoolValue{Value: true},
		MembersCanInviteOutsideCollaborators:   &wrapperspb.BoolValue{Value: false},
		AllowsPrivateRepositoryForking:         &wrapperspb.BoolValue{Value: true},
		MembersCanCreatePages:                  &wrapperspb.BoolValue{Value: true},
		MembersCanChangeRepoVisibility:         &wrapperspb.BoolValue{Value: false},
		MembersCanDeleteRepositories:           &wrapperspb.BoolValue{Value: true},
		MembersCanDeleteIssues:                 &wrapperspb.BoolValue{Value: false},
		DisplayCommenterFullNameSettingEnabled: &wrapperspb.BoolValue{Value: true},
		ReadersCanCreateDiscussions:            &wrapperspb.BoolValue{Value: false},
		MembersCanCreateTeams:                  &wrapperspb.BoolValue{Value: true},
		MembersCanViewDependencyInsights:       &wrapperspb.BoolValue{Value: true},
	}

	expectedRepoDefaults := &v1.RepositoryDefault{
		RepositoryDefaultBranch: &wrapperspb.StringValue{Value: "main"},
		CommitSignoff:           &wrapperspb.BoolValue{Value: true},
		Labels:                  expectedRepoLabels,
	}

	// Check top-level organization settings
	require.Equal(t, "organizationsettings-http://github.test/test-org", v1OrgSettings.ResourceId)
	require.Equal(t, "http://github.test/test-org", v1OrgSettings.OrganizationResourceId)

	// Check member privileges
	require.Equal(t, expectedMemberPrivileges, v1OrgSettings.MemberPrivileges)

	// Check repository defaults
	require.Equal(t, expectedRepoDefaults, v1OrgSettings.RepositoryDefault)

	// Check webhooks
	require.Equal(t, expectedWebhooks, v1OrgSettings.Webhooks)
}

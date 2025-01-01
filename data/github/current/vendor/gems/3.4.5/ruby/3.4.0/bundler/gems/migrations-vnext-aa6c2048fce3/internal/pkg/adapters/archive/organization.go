package archive

import (
	"fmt"
	"time"

	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type (
	// Member struct represents the members of the organization
	Member struct {
		User  string `json:"user"`
		Role  string `json:"role"`
		State string `json:"state"`
	}

	// Webhook struct represents the webhooks associated with the organization
	Webhook struct {
		PayloadURL            string   `json:"payload_url"`
		ContentType           string   `json:"content_type"`
		EventTypes            []string `json:"event_types"`
		EnableSSLVerification bool     `json:"enable_ssl_verification"`
		Active                bool     `json:"active"`
	}

	// MemberPrivileges struct represents the privileges that members of the organization have
	MemberPrivileges struct {
		DefaultRepositoryPermission            *string `json:"default_repository_permission,omitempty"`
		MembersCanCreatePublicRepositories     *bool   `json:"members_can_create_public_repositories,omitempty"`
		MembersCanCreatePrivateRepositories    *bool   `json:"members_can_create_private_repositories,omitempty"`
		MembersCanCreateInternalRepositories   *bool   `json:"members_can_create_internal_repositories,omitempty"`
		MembersCanInviteOutsideCollaborators   *bool   `json:"members_can_invite_outside_collaborators,omitempty"`
		AllowsPrivateRepositoryForking         *bool   `json:"allows_private_repository_forking,omitempty"`
		MembersCanCreatePages                  *bool   `json:"members_can_create_pages,omitempty"`
		MembersCanChangeRepoVisibility         *bool   `json:"members_can_change_repo_visibility,omitempty"`
		MembersCanDeleteRepositories           *bool   `json:"members_can_delete_repositories,omitempty"`
		MembersCanDeleteIssues                 *bool   `json:"members_can_delete_issues,omitempty"`
		DisplayCommenterFullNameSettingEnabled *bool   `json:"display_commenter_full_name_setting_enabled,omitempty"`
		ReadersCanCreateDiscussions            *bool   `json:"readers_can_create_discussions,omitempty"`
		MembersCanCreateTeams                  *bool   `json:"members_can_create_teams,omitempty"`
		MembersCanViewDependencyInsights       *bool   `json:"members_can_view_dependency_insights,omitempty"`
	}

	// Label struct represents the labels used in repository defaults
	Label struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		Color       string `json:"color"`
		Default     bool   `json:"default"`
	}

	// RepositoryDefaults struct represents default settings for repositories
	RepositoryDefaults struct {
		RepositoryDefaultBranch *string `json:"repository_default_branch"`
		CommitSignoff           *bool   `json:"commit_signoff"`
		RepositoryLabels        []Label `json:"repository_labels"`
	}

	// Organization struct represents the main organization object
	Organization struct {
		Type               string              `json:"type"`
		URL                string              `json:"url"`
		Login              string              `json:"login"`
		Name               string              `json:"name"`
		Description        string              `json:"description"`
		Website            string              `json:"website"`
		Location           string              `json:"location"`
		Email              string              `json:"email"`
		Members            []Member            `json:"members"`
		OwnersTeam         string              `json:"owners_team"`
		Webhooks           []*Webhook          `json:"webhooks,omitempty"`
		CreatedAt          time.Time           `json:"created_at"`
		MemberPrivileges   *MemberPrivileges   `json:"member_privileges,omitempty"`
		RepositoryDefaults *RepositoryDefaults `json:"repository_defaults,omitempty"`
		Labels             []Label             `json:"labels"`
	}
)

// ToV1Organization converts an Organization to a v1.Organization.
func (o *Organization) ToV1Organization() (*v1.Organization, error) {
	return &v1.Organization{
		ResourceId: o.URL,
		Name:       o.Name,
		Login:      o.Login,
	}, nil
}

// ToV1InitialOrganizationSettings converts an Organization to a v1.InitialOrganizationSettings.
func (o *Organization) ToV1InitialOrganizationSettings() *v1.InitialOrganizationSettings {
	settings := &v1.InitialOrganizationSettings{
		ResourceId:             fmt.Sprintf("organizationsettings-%s", o.URL),
		OrganizationResourceId: o.URL,
	}

	if o.Webhooks != nil {
		webhooks := []*v1.Webhook{}
		for _, w := range o.Webhooks {
			webhooks = append(webhooks, &v1.Webhook{
				PayloadUrl:            w.PayloadURL,
				Active:                w.Active,
				EnableSslVerification: w.EnableSSLVerification,
				EventTypes:            w.EventTypes,
				ContentType:           w.ContentType,
			})
		}
		settings.Webhooks = webhooks
	}

	// The API will not accept MemberPrivileges being nil.
	settings.MemberPrivileges = &v1.MemberPrivileges{
		// The API will error if the following are nil.
		// These are default values.
		MembersCanCreatePublicRepositories: &wrapperspb.BoolValue{
			Value: true,
		},
		MembersCanCreateInternalRepositories: &wrapperspb.BoolValue{
			Value: true,
		},
		MembersCanCreatePrivateRepositories: &wrapperspb.BoolValue{
			Value: true,
		},
	}
	if o.MemberPrivileges != nil {
		settings.MemberPrivileges = &v1.MemberPrivileges{
			DefaultRepositoryPermission:            setStrIfNotNil(o.MemberPrivileges.DefaultRepositoryPermission),
			MembersCanCreatePublicRepositories:     setBoolIfNotNil(o.MemberPrivileges.MembersCanCreatePublicRepositories),
			MembersCanCreatePrivateRepositories:    setBoolIfNotNil(o.MemberPrivileges.MembersCanCreatePrivateRepositories),
			MembersCanCreateInternalRepositories:   setBoolIfNotNil(o.MemberPrivileges.MembersCanCreateInternalRepositories),
			MembersCanInviteOutsideCollaborators:   setBoolIfNotNil(o.MemberPrivileges.MembersCanInviteOutsideCollaborators),
			AllowsPrivateRepositoryForking:         setBoolIfNotNil(o.MemberPrivileges.AllowsPrivateRepositoryForking),
			MembersCanCreatePages:                  setBoolIfNotNil(o.MemberPrivileges.MembersCanCreatePages),
			MembersCanChangeRepoVisibility:         setBoolIfNotNil(o.MemberPrivileges.MembersCanChangeRepoVisibility),
			MembersCanDeleteRepositories:           setBoolIfNotNil(o.MemberPrivileges.MembersCanDeleteRepositories),
			MembersCanDeleteIssues:                 setBoolIfNotNil(o.MemberPrivileges.MembersCanDeleteIssues),
			DisplayCommenterFullNameSettingEnabled: setBoolIfNotNil(o.MemberPrivileges.DisplayCommenterFullNameSettingEnabled),
			ReadersCanCreateDiscussions:            setBoolIfNotNil(o.MemberPrivileges.ReadersCanCreateDiscussions),
			MembersCanCreateTeams:                  setBoolIfNotNil(o.MemberPrivileges.MembersCanCreateTeams),
			MembersCanViewDependencyInsights:       setBoolIfNotNil(o.MemberPrivileges.MembersCanViewDependencyInsights),
		}
	}
	// The API will not accept RepositoryDefaults being nil.
	settings.RepositoryDefault = &v1.RepositoryDefault{}
	if o.RepositoryDefaults != nil {
		labels := []*v1.Label{}
		for _, l := range o.RepositoryDefaults.RepositoryLabels {
			labels = append(labels, &v1.Label{
				Name:        l.Name,
				Color:       l.Color,
				Default:     l.Default,
				Description: l.Description,
			})
		}
		settings.RepositoryDefault = &v1.RepositoryDefault{
			RepositoryDefaultBranch: setStrIfNotNil(o.RepositoryDefaults.RepositoryDefaultBranch),
			CommitSignoff:           setBoolIfNotNil(o.RepositoryDefaults.CommitSignoff),
			Labels:                  labels,
		}
	}

	return settings
}

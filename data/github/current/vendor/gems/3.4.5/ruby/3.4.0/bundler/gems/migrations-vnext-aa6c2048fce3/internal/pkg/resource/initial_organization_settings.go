package resource

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/client"
	octov1 "github.com/github/migrations-vnext/internal/pkg/octoshift/imports/v1"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
)

type (
	initialOrganizationSettings struct {
		baseHandler
		pb *v1.InitialOrganizationSettings
	}

	// InitialOrganizationSettingsError is an error type for a failed organization settings
	// import. Most resources return a Twirp error, but this resource may also fail without
	// a Twirp error at import time. This error type is used to handle that case so that
	// it can be detected by the caller without having to parse the error message.
	InitialOrganizationSettingsError struct {
		Errors []string
	}
)

var _ handler = (*initialOrganizationSettings)(nil)

func newInitialOrganizationSettings(pb *v1.InitialOrganizationSettings, logger log.Logger) *initialOrganizationSettings {
	return &initialOrganizationSettings{
		baseHandler: baseHandler{logger},
		pb:          pb,
	}
}

func (o *initialOrganizationSettings) resourceID() string {
	return o.pb.ResourceId
}

func (o *initialOrganizationSettings) dependencies() (*transformedDeps, error) {
	deps := newTransformedDeps()
	deps.int64Deps.Add(o.pb.OrganizationResourceId)
	return deps, nil
}

func (o *initialOrganizationSettings) load(ctx context.Context, importer client.Importer, resolved resolvedIDsByResource) error {
	webhooks := []*octov1.Webhook{}
	for _, w := range o.pb.Webhooks {
		webhooks = append(webhooks, &octov1.Webhook{
			PayloadUrl:            w.PayloadUrl,
			Active:                w.Active,
			EnableSslVerification: w.EnableSslVerification,
			EventTypes:            w.EventTypes,
			ContentType:           w.ContentType,
		})
	}
	orgID := resolved[o.pb.OrganizationResourceId].int64Val

	privileges := &octov1.MemberPrivileges{
		DefaultRepositoryPermission:            o.pb.MemberPrivileges.DefaultRepositoryPermission,
		MembersCanCreatePublicRepositories:     o.pb.MemberPrivileges.MembersCanCreatePublicRepositories,
		MembersCanCreatePrivateRepositories:    o.pb.MemberPrivileges.MembersCanCreatePrivateRepositories,
		MembersCanCreateInternalRepositories:   o.pb.MemberPrivileges.MembersCanCreateInternalRepositories,
		MembersCanInviteOutsideCollaborators:   o.pb.MemberPrivileges.MembersCanInviteOutsideCollaborators,
		AllowsPrivateRepositoryForking:         o.pb.MemberPrivileges.AllowsPrivateRepositoryForking,
		MembersCanCreatePages:                  o.pb.MemberPrivileges.MembersCanCreatePages,
		MembersCanChangeRepoVisibility:         o.pb.MemberPrivileges.MembersCanChangeRepoVisibility,
		MembersCanDeleteRepositories:           o.pb.MemberPrivileges.MembersCanDeleteRepositories,
		MembersCanDeleteIssues:                 o.pb.MemberPrivileges.MembersCanDeleteIssues,
		DisplayCommenterFullNameSettingEnabled: o.pb.MemberPrivileges.DisplayCommenterFullNameSettingEnabled,
		ReadersCanCreateDiscussions:            o.pb.MemberPrivileges.ReadersCanCreateDiscussions,
		MembersCanCreateTeams:                  o.pb.MemberPrivileges.MembersCanCreateTeams,
		MembersCanViewDependencyInsights:       o.pb.MemberPrivileges.MembersCanViewDependencyInsights,
	}

	convertedLabels := make([]*octov1.Label, len(o.pb.RepositoryDefault.Labels))
	for i, label := range o.pb.RepositoryDefault.Labels {
		convertedLabels[i] = &octov1.Label{
			Name:        label.Name,
			Color:       label.Color,
			Default:     label.Default,
			Description: label.Description,
		}
	}

	repoDefault := &octov1.RepositoryDefault{
		RepositoryDefaultBranch: o.pb.RepositoryDefault.RepositoryDefaultBranch,
		CommitSignoff:           o.pb.RepositoryDefault.CommitSignoff,
		Labels:                  convertedLabels,
	}

	req := &octov1.ImportOrganizationSettingsRequest{
		TargetOrgId:       orgID,
		MemberPrivileges:  privileges,
		RepositoryDefault: repoDefault,
		Webhooks:          webhooks,
	}
	res, err := importer.ImportOrganizationSettings(ctx, req)
	if err != nil {
		o.logger.WithError(err).Error("failed to import organization settings")
		return fmt.Errorf("failed to update organization settings: %w", err)
	}
	if len(res.OrganizationSettingsErrors) > 0 {
		o.logger.Error("failed to update organization settings", kvp.Any("msg", res.OrganizationSettingsErrors))
		return &InitialOrganizationSettingsError{Errors: res.OrganizationSettingsErrors}
	}
	return nil
}

// Error returns a string representation of the error
func (e *InitialOrganizationSettingsError) Error() string {
	return fmt.Sprintf("failed to update organization settings: %v", e.Errors)
}

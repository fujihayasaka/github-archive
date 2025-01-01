# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseTeamRoleAssignmentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include BusinessTeamHandlers
  include RoleAssignments::AvatarOrgsHelper

  depends_on_clusters ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Copilot,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    only: [:index]

  before_action :business_teams_enabled_required
  before_action only: [:index] do
    T.bind(self, Businesses::Concerns::BusinessAccess)
    business_access_required(allow_members: true)
  end
  before_action :custom_enterprise_roles_enabled
  before_action :read_enterprise_roles_required, only: [:index]
  before_action :write_enterprise_roles_required, except: [:index]
  before_action :validate_team_parameter, only: [:index]
  before_action :business_owner_required

  sig { void }
  def index
    payload = business_team_roles_payload

    render_react_app(
      app_name: "business-teams",
      payload: payload,
      layout: "react_business",
      title: "Enterprise team roles",
      page_data: { sidebar: :people, selected_link: :business_teams },
    )
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def business_team_roles_payload
    role_fetcher = RoleAssignments::FetchActorRoleAssignments.new(actor: business_team)
    assignments = role_fetcher.enterprise_role_assignments.role_assignments

    {
      orgAssignmentsEnabled: current_business.erp_feature_enabled?(:enterprise_teams_org_assignment),
      enterpriseSlug: current_business.slug,
      enterpriseTeam: {
        id: business_team.id,
        name: business_team.name,
        slug: business_team.slug,
        description: business_team.description,
        totalMemberCount: business_team.members.count,
        totalOrganizationCount: business_team.organizations.count,
        totalRoleCount: viewer_permissions[:read_enterprise_custom_enterprise_role] ? role_fetcher.total_role_assignments : 0,
        organizationSelectionType: business_team.organization_selection_type,
        linkedToExternalGroup: business_team.external_group_team.present?,
      },
      avatarOrgs: avatar_orgs,
      roleAssignments: assignments,
      viewerPermissions: viewer_permissions,
    }
  end

  sig { void }
  def custom_enterprise_roles_enabled
    render_404 unless this_business&.custom_enterprise_roles_supported?
  end

  sig { void }
  def validate_team_parameter
    business_validate_team_parameter
  end

  sig { void }
  def business_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business) && current_business.custom_enterprise_roles_supported?
  end

  sig { void }
  def read_enterprise_roles_required
    render_404 unless viewer_permissions[:read_enterprise_custom_enterprise_role]
  end

  sig { void }
  def write_enterprise_roles_required
    unless viewer_permissions[:write]
      respond_to do |format|
        format.html { render_404 }
        format.json { render status: :forbidden, json: { success: false, message: "You do not have sufficient permissions to perform this action." } }
      end
    end
  end
end

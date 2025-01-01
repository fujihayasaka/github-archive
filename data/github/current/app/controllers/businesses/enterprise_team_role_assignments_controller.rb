# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseTeamRoleAssignmentsController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include BusinessTeamHandlers

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
  before_action :write_enterprise_roles_required, except: [:index]
  before_action :validate_team_parameter, only: [:index]
  before_action :business_owner_required

  sig { void }
  def index
    business_team = this_business.business_teams.find_by(slug: params[:team_slug])

    payload = business_team_roles_payload(current_business, business_team)

    render_react_app(
      app_name: "business-teams",
      payload: payload,
      layout: "react_business",
      title: "Enterprise team roles",
      page_data: { sidebar: :people, selected_link: :business_teams },
    )
  end

  private

  sig { params(current_business: Business, business_team: BusinessTeam).returns(T::Hash[Symbol, T.untyped]) }
  def business_team_roles_payload(current_business, business_team)
    role_fetcher = RoleAssignments::FetchActorRoleAssignments.new(actor: business_team)
    assignments = role_fetcher.paginate_enterprise_role_assignments(page: 1).role_assignments
    roles_by_id = EnterpriseRole.includes(:permissions).where(id: assignments.map(&:role).map(&:id)).index_by(&:id)
    fgps = assignments.each_with_object({}) do |a, h|
      h[a.role.id] = { Enterprise: EnterpriseFgpMetadata.for_role(roles_by_id[a.role.id]) }
    end

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
        totalRoleCount: role_fetcher.total_role_assignments,
      },
      roleAssignments: assignments,
      fgps: fgps,
      viewerPermissions: viewer_permissions,
    }
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
  def write_enterprise_roles_required
    unless viewer_permissions[:write]
      respond_to do |format|
        format.html { render_404 }
        format.json { render status: :forbidden, json: { success: false, message: "You do not have sufficient permissions to perform this action." } }
      end
    end
  end

  sig { returns(T::Hash[Symbol, T::Boolean]) }
  memoize def viewer_permissions
    return { read: false, write: false } unless current_user && this_business

    permissions = Authz.domain.check_multiple_permissions(
      T.must(current_user),
      [:read_enterprise_custom_enterprise_role, :write_enterprise_custom_enterprise_role],
      this_business,
    )
    {
      read: permissions[:read_enterprise_custom_enterprise_role],
      write: permissions[:write_enterprise_custom_enterprise_role],
    }
  end
end

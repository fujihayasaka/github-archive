# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseTeamOrganizationAssignmentsController < Businesses::BusinessController
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
  before_action :business_validate_team_parameter, only: [:index, :create, :destroy]
  before_action :business_owner_required

  PER_PAGE = 30

  sig { void }
  def index
    payload = business_team_organizations_payload(current_business, business_team)
    render_react_app(
      app_name: "business-teams",
      payload: payload,
      layout: "react_business",
      title: "Enterprise team organizations",
      page_data: { sidebar: :people, selected_link: :business_teams },
    )
  end

  sig { void }
  def create
    unless %w[selected disabled].include?(business_team.organization_selection_type)
      return render json: { error: "Invalid selection type" }, status: :bad_request
    end

    organization_ids = Array(params[:organizationIds]).map(&:to_i).uniq

    if organization_ids.empty? || organization_ids.any?(&:zero?)
      return render json: { error: "Invalid organization IDs" }, status: :bad_request
    end

    existing_ids = business_team.organizations.where(id: organization_ids).pluck(:id)
    if existing_ids.any?
      return render json: { error: "Failed to add organizations: Some organizations are already assigned" }, status: :unprocessable_entity
    end

    limit = business_team.limit_organization_assignments
    new_total = business_team.organizations.count + organization_ids.length

    if new_total > limit
      return render json: { error: "Adding all specified organizations would exceed the limit of #{limit}" }, status: :bad_request
    end

    if business_team.organization_selection_type == "disabled"
      business_team.update!(organization_selection_type: "selected")
    end

    business_team.add_to_organizations(org_ids: organization_ids)
    render json: { message: "Organizations successfully added" }, status: :ok
  end

  sig { void }
  def destroy
    unless business_team.organization_selection_type == "selected"
      return render json: { error: "Invalid selection type" }, status: :bad_request
    end

    organization_ids = Array(params[:organizationIds]).map(&:to_i).uniq

    if organization_ids.empty? || organization_ids.any?(&:zero?)
      return render json: { error: "Invalid organization IDs" }, status: :bad_request
    end

    business_team.remove_from_organizations(org_ids: organization_ids)
    render json: { message: "Organizations successfully removed" }, status: :ok
  end

  private

  sig { params(current_business: Business, business_team: BusinessTeam).returns(T::Hash[Symbol, T.untyped]) }
  def business_team_organizations_payload(current_business, business_team)
    role_fetcher = RoleAssignments::FetchActorRoleAssignments.new(actor: business_team)
    organizations = business_team.organizations
      .includes(:profile)
      .references(:profile)
      .order(Arel.sql("COALESCE(profiles.name, users.display_login)"))
      .limit(PER_PAGE)
      .map do |organization|
        organization_payload(organization)
      end
    {
      orgAssignmentsEnabled: current_business.erp_feature_enabled?(:enterprise_teams_org_assignment),
      enterpriseSlug: current_business.slug,
      organizations: organizations,
      enterpriseTeam: {
        id: business_team.id,
        name: business_team.name,
        slug: business_team.slug,
        description: business_team.description,
        totalMemberCount: business_team.members.count,
        totalOrganizationCount: business_team.organizations.count,
        totalRoleCount: role_fetcher.total_role_assignments,
      },
    }
  end

  sig { void }
  def business_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business) && current_business.erp_feature_enabled?(:enterprise_teams_org_assignment)
  end
end

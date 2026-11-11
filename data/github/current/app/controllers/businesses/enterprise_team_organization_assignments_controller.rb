# typed: strict
# frozen_string_literal: true

class Businesses::EnterpriseTeamOrganizationAssignmentsController < Businesses::BusinessController
  include BusinessTeamHandlers
  include ApplicationController::VerifiedFetchDependency

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

  allow_verified_fetch only: [:create, :destroy]
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
    page = (params[:page] || 1).to_i
    order = params[:order] || "Ascending"
    sort = params[:sort] || "Name"
    query = params[:query]

    payload = business_team_organizations_payload(current_business, business_team, {
      page: page,
      sort: sort,
      order: order,
      query: query
    })
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

    organization_ids = Array(params[:organization_ids]).map(&:to_i).uniq

    if organization_ids.empty? || organization_ids.any?(&:zero?)
      return render json: { error: "Invalid organization IDs" }, status: :bad_request
    end

    existing_ids = business_team.organizations.where(id: organization_ids).pluck(:id)
    if existing_ids.any?
      return render json: { error: "Failed to add organizations: Some organizations are already assigned" }, status: :unprocessable_entity
    end

    limit = business_team.organization_assignments_limit
    new_total = business_team.organizations.count + organization_ids.length

    if new_total > limit
      return render json: { error: "Adding all specified organizations would exceed the limit of #{limit}" }, status: :bad_request
    end

    if business_team.organization_selection_type == "disabled"
      business_team.update!(organization_selection_type: "selected")
    end

    status = business_team.add_to_organizations(org_ids: organization_ids)
    return render json: { error: status.message }, status: :unprocessable_entity if status.error?
    render json: { message: "Organizations successfully added" }, status: :ok
  end

  sig { void }
  def destroy
    if role_fetcher.is_enterprise_security_manager?
      return render json: { error: "You can’t modify the organization list while the Enterprise Security Manager role is assigned." }, status: :forbidden
    end

    unless business_team.organization_selection_type == "selected"
      return render json: { error: "Invalid selection type" }, status: :bad_request
    end

    organization_ids = Array(params[:organization_ids]).map(&:to_i).uniq

    if organization_ids.empty? || organization_ids.any?(&:zero?)
      return render json: { error: "Invalid organization IDs" }, status: :bad_request
    end

    business_team.remove_from_organizations(org_ids: organization_ids)
    render json: { message: "Organizations successfully removed" }, status: :ok
  end

  private

  sig do
    params(
      current_business: Business,
      business_team: BusinessTeam,
      params: T::Hash[T.untyped, T.untyped]
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def business_team_organizations_payload(current_business, business_team, params)
    page = params[:page]
    sort = params[:sort]
    order = params[:order]
    query = params[:query]

    direction = :asc
    direction = :desc if order == "Descending"
    filter = query.to_s.strip
    query = ActiveRecord::Base.sanitize_sql_like(filter.downcase)

    organizations_collection = nil
    organizations = if business_team.organization_selection_type == "selected"
      case sort
      when "Last added"
        # Use the join table directly to access updated_at for sorting
        scope = business_team.business_team_org_assignments
          .includes(organization: :profile)

        # Apply query filter if present
        if query.present?
          scope = scope.merge(Organization.like_login_or_profile_name(query))
        end

        organizations_collection = scope
          .order(updated_at: direction)
          .paginate(page: page, per_page: PER_PAGE)
        organizations_collection.map { |assignment| organization_payload(assignment.organization) }
      else # "Name"
        scope = business_team.organizations
          .includes(:profile)
          .references(:profile)

        # Apply query filter if present
        if query.present?
          scope = scope.like_login_or_profile_name(query)
        end

        organizations_collection = scope
          .order(Arel.sql("COALESCE(profiles.name, users.display_login) #{direction}"))
          .paginate(page: page, per_page: PER_PAGE)
        organizations_collection.map { |organization| organization_payload(organization) }
      end
    end

    {
      orgAssignmentsEnabled: true,
      isEnterpriseSecurityManager: role_fetcher.is_enterprise_security_manager?,
      enterpriseTeamsOrgAssignmentLimit: business_team.organization_assignments_limit,
      enterpriseSlug: current_business.slug,
      organizations: organizations,
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
        avatarUrl: business_team.primary_avatar_url,
      },
      meta: {
        pageSize: PER_PAGE,
        page: page,
        sortOption: sort,
        orderOption: order,
        queryOrgCount: organizations_collection ? organizations_collection.total_entries : 0,
      },
      viewerPermissions: viewer_permissions,
    }
  end

  sig { void }
  def business_teams_enabled_required
    render_404 unless BusinessTeam.enabled_for_enterprise?(business: current_business)
  end

  sig { returns(RoleAssignments::FetchActorRoleAssignments) }
  memoize def role_fetcher
    RoleAssignments::FetchActorRoleAssignments.new(actor: business_team)
  end
end

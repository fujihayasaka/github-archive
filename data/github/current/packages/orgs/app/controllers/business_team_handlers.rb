# typed: strict
# frozen_string_literal: true

module BusinessTeamHandlers
  include GitHub::Memoizer
  include BusinessesHelper
  extend ActiveSupport::Concern
  extend T::Helpers

  PER_PAGE = 30 # Rails default

  requires_ancestor { Businesses::BusinessController }

  abstract!

  sig { abstract.returns(T.nilable(User)) }
  def current_user; end

  sig { returns(BusinessTeam) }
  memoize def business_team
    current_business.business_teams.find_by!(slug: params[:team_slug])
  end

  sig { void }
  def business_validate_team_parameter
    begin
      business_team
    rescue ActiveRecord::RecordNotFound
      return render(json: { data: { error: "Team not found." } }, status: :not_found) if request.xhr?
      render_404
    end
  end

  sig do
    params(
      current_business: Business,
    ).void
  end
  def business_teams_index(current_business:)
    team_name_filter = params[:team].to_s.strip || ""
    page = (params[:page].presence || 1).to_i
    page_size = 10
    sort_option = params[:sort] || "Name"
    order_option = params[:order] || "Ascending"

    valid_sort_options = ["Last added", "Name", "Ascending", "Descending"]
    unless valid_sort_options.include?(sort_option)
      return render_404
    end

    T.unsafe(self).class.react_bundle_name = "business-teams"
    render_react_app(
      payload: business_teams_index_payload(current_business, team_name_filter, page, page_size, sort_option, order_option),
      layout: "react_business",
      title: "Enterprise teams",
      page_data: { sidebar: :people, selected_link: :business_teams },
    )
  end

  sig do
    params(
      current_business: Business,
    ).void
  end
  def business_teams_new(current_business:)
    T.unsafe(self).class.react_bundle_name = "business-teams"
    render_react_app(
      payload: new_business_team_payload,
      layout: "react_business",
      title: "Create Enterprise team",
      page_data: { sidebar: :people, selected_link: :business_teams },
    )
  end

  sig do
    params(
      current_business: Business,
    ).void
  end
  def business_teams_edit(current_business:)
    T.unsafe(self).class.react_bundle_name = "business-teams"
    business_team = current_business.business_teams.find_by(slug: params[:team_slug])
    if !business_team.present?
      render_404
      return
    end

    render_react_app(
      payload: new_business_team_payload(business_team),
      layout: "react_business",
      title: "Edit Enterprise team",
      page_data: { sidebar: :people, selected_link: :business_teams },
    )
  end

  sig do
    params(
      current_business: Business,
    ).void
  end
  def business_teams_create(current_business:)
    team_params = params.permit(:teamName, :teamDescription, :organizationSelectionType, :selectedOrganizationIds, :slug)
    validation_result = validate_team_org_params(team_params)
    return render(json: { data: { error: validation_result[:error] } }, status: :bad_request) if validation_result[:valid] == false

    team_name = team_params[:teamName]
    description = team_params[:teamDescription]
    organization_selection_type = team_params[:organizationSelectionType] || "all"
    selected_organization_ids = validation_result[:selected_organization_ids]

    begin
      business_team = EnterpriseTeams::Factory.create_business_team(
        enterprise: current_business,
        team_name: team_name,
        description: description,
        organization_selection_type: organization_selection_type.to_sym,
      )
      business_team.add_to_organizations(org_ids: selected_organization_ids)
    rescue ActiveRecord::RecordInvalid => e
      return render(json: { data: { error: e.record.errors.full_messages.to_sentence } }, status: :bad_request)
    end

    render(json: {
      data: {
        redirect: enterprise_team_path(slug: current_business.slug, team_slug: business_team.slug)
      }
    }, status: :ok)
  end

  sig do
    params(
      current_business: Business,
    ).void
  end
  def business_teams_update(current_business:)
    team_params = params.permit(:teamName, :teamDescription, :organizationSelectionType, :selectedOrganizationIds, :slug, :team_slug)
    validation_result = validate_team_org_params(team_params)
    return render(json: { data: { error: validation_result[:error] } }, status: :bad_request) if validation_result[:valid] == false

    organization_selection_type = team_params[:organizationSelectionType] || "all"
    selected_organization_ids = validation_result[:selected_organization_ids]

    begin
      business_team = EnterpriseTeams::Factory.update_business_team(
        enterprise: current_business,
        team_slug: params[:team_slug],
        team_name: team_params[:teamName],
        description: team_params[:teamDescription],
        organization_selection_type: organization_selection_type.to_sym,
      )
      BusinessTeam.transaction do
        case organization_selection_type
        when "all", "disabled"
          business_team.business_team_org_assignments.destroy_all
        when "selected"
          business_team.remove_from_organizations(org_ids: business_team.organization_ids - selected_organization_ids)
          business_team.add_to_organizations(org_ids: selected_organization_ids - business_team.organization_ids)
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      return render(json: { data: { error: e.record.errors.full_messages.to_sentence } }, status: :bad_request)
    rescue ActiveRecord::RecordNotFound
      return render(json: { data: { error: "Team not found." } }, status: :not_found)
    end

    render(json: {
      data: {
        redirect: enterprise_team_path(slug: current_business.slug, team_slug: business_team.slug)
      }
    }, status: :ok)
  end

  sig do
    params(
      current_business: Business,
      team_slugs: T::Array[String],
    ).void
  end
  def business_teams_destroy(current_business:, team_slugs: [])
    selected_teams = current_business.business_teams.where(slug: team_slugs)
    return render(json: { data: { error: "No team found." } }, status: :not_found) unless selected_teams.exists?

    begin
      EnterpriseTeams::Editor.bulk_delete_business_teams(business: current_business, team_slugs: team_slugs)
    rescue ActiveRecord::RecordNotFound => e
      return render(json: { data: { error: e.message } }, status: :not_found)
    end

    render(json: { data: { redirect: enterprise_teams_url(current_business) } }, status: :ok)
  end

  sig { params(current_business: Business, business_team: BusinessTeam).void }
  def business_team_members_index(current_business, business_team)
    T.unsafe(self).class.react_bundle_name = "business-teams"
    query = params[:query] || ""
    page = (params[:page] || 1).to_i
    sort = params[:sort] || "Name"
    order = params[:order] || "Ascending"

    payload = business_team_members_payload(current_business, business_team, { query: query, page: page, sort: sort, order: order })
    if request.xhr?
      render(json: payload, status: :ok)
    else
      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Enterprise team members",
        page_data: { sidebar: :people, selected_link: :business_teams },
      )
    end
  end

  sig { params(current_business: Business, business_team: BusinessTeam, query_params: T::Hash[T.untyped, T.untyped]).returns(T::Hash[Symbol, T.untyped]) }
  def business_team_members_payload(current_business, business_team, query_params)
    filter = params[:query].to_s.strip
    query = ActiveRecord::Base.sanitize_sql_like(filter.downcase)
    memberships = business_team.members
    total_member_count = memberships.count
    memberships = memberships.like_login_or_profile_name(query)

    direction = :asc
    direction = :desc if query_params[:order] == "Descending"
    memberships = memberships.order(Arel.sql("COALESCE(name, display_login) #{direction}"))
    memberships = memberships.paginate(page: query_params[:page], per_page: PER_PAGE)

    {
      orgAssignmentsEnabled: current_business.erp_feature_enabled?(:enterprise_teams_org_assignment),
      enterpriseSlug: current_business.slug,
      enterpriseTeamMembersLimit: current_business.business_team_member_limit,
      enterpriseTeam: {
        name: business_team.name,
        slug: business_team.slug,
        description: business_team.description,
        totalMemberCount: total_member_count,
        totalOrganizationCount: business_team.organizations.count,
        totalRoleCount: RoleAssignments::FetchActorRoleAssignments.new(actor: business_team).total_role_assignments
      },
      meta: {
        filter: filter,
        page: query_params[:page],
        pageSize: PER_PAGE,
        sortOption: "Name",
        orderOption: query_params[:order],
        queryMemberCount: memberships.total_entries,
        membersAllowedToAdd: business_team.members_allowed_to_add,
        memberLimitReached: business_team.member_limit_reached?
      },
      members: memberships.map do |member|
        business_team_member_payload(member)
      end
    }
  end

  sig { params(user: User).returns(T::Hash[Symbol, T.untyped]) }
  def business_team_member_payload(user)
    {
      displayLogin: user.display_login,
      profileName: user.profile_name || user.display_login,
      id: user.id,
      avatarUrl: user.primary_avatar_url
    }
  end

  sig { params(current_business: Business).void }
  def business_team_members_create(current_business)
    business_team = T.must(current_business.business_teams.find_by(slug: params[:team_slug]))
    body = JSON.parse(request&.body.read)
    users = if body["select_all_in_enterprise"].present? && body["select_all_in_enterprise"] == true
      business_team.eligible_members_in_enterprise(current_user).compact
    elsif body["user_ids"].present? && body["user_ids"].is_a?(Array) && body["user_ids"].all?(Integer)
      business_team.eligible_members_in_enterprise(current_user).where(id: body["user_ids"]).compact
    else
      return render(json: { error: "Missing user_ids" }, status: 400)
    end

    business_team.bulk_add_members(users[0..(PER_PAGE - 1)], caller_type: :business_team)

    if users.size > PER_PAGE
      BusinessTeamsAddMembersJob.perform_later(business_team, users[PER_PAGE..])
    end
    render(json: {}, status: :ok)
  end

  sig { void }
  def business_team_members_destroy
    users = User.where(id: params[:user_ids])
    business_team.bulk_remove_members(users: users, caller_type: :business_team)

    render(json: {
      data: {
        redirect: enterprise_team_members_path(slug: current_business.slug, team_slug: business_team.slug)
      }
    }, status: :ok)
  end

  sig { params(business_team: T.nilable(BusinessTeam)).returns(T::Hash[Symbol, T.untyped]) }
  def new_business_team_payload(business_team = nil)
    payload = {
      enterpriseSlug: current_business.slug,
      baseUrl: enterprise_teams_path(current_business.slug),
      allOrgsCount: current_business.organizations.count,
      enterpriseTeamsLimit: current_business.business_teams_per_business_limit,
      enterpriseTeamsLimitReached: current_business.business_teams_limit_reached?,
      enterpriseTeamsOrgAssignmentLimit: current_business.business_team_organization_assignment_limit,
      canSelectAllOrganizations: current_business.erp_feature_enabled?(:enterprise_teams_org_assignment),
      canSelectOrganizationAssignmentType: current_business.erp_feature_enabled?(:enterprise_teams_org_assignment),
      preventEditOrganizations: business_team.present? && current_business.erp_feature_enabled?(:enterprise_teams_forbid_edit_form_org_selection)
    }

    if business_team.present?
      payload[:enterpriseTeam] = {
        name: business_team.name,
        slug: business_team.slug,
        description: business_team.description,
        organizationSelectionType: business_team.organization_selection_type,
        url: enterprise_team_path(current_business.slug, business_team.slug),
      }
      sorted_orgs = business_team.organizations.includes(:profile)
        .order(Arel.sql("COALESCE(profiles.name, users.display_login)"))
        .references(:profile)
      if business_team.organization_selection_type == "selected"
        payload[:enterpriseTeam][:selectedOrganizations] = sorted_orgs.map { |organization| organization_payload(organization) }
      end
    end

    payload
  end

  sig { params(current_business: Business, team_name_filter: String, page: Integer, page_size: Integer, sort_option: String, order_option: String).returns(T::Hash[Symbol, T.untyped]) }
  def business_teams_index_payload(current_business, team_name_filter, page, page_size, sort_option, order_option)
    business_teams_query = current_business.business_teams
    business_teams_query = business_teams_query.where("name LIKE ?", "%#{team_name_filter}%") unless team_name_filter.empty?

    order = :asc
    order = :desc if order_option == "Descending"
    case sort_option
    when "Last added"
      business_teams_query = business_teams_query.order(created_at: order)
    when "Name"
      business_teams_query = business_teams_query.order(name: order)
    else
      business_teams_query = business_teams_query.order(name: order)
    end

    business_teams = business_teams_query.paginate(
      page: page,
      per_page: page_size
    )
    total_teams_count = business_teams.total_entries

    enterprise_team_list = business_teams.map { |team| team_payload(team, current_business) }

    {
      enterpriseSlug: current_business.slug,
      enterpriseTeams: enterprise_team_list,
      enterpriseTeamsLimit: current_business.business_teams_per_business_limit,
      enterpriseTeamsLimitReached: current_business.business_teams_limit_reached?,
      totalTeamsCount: total_teams_count,
      createTeamUrl: new_enterprise_team_enterprise_path(current_business.slug, only_path: true),
      isOwner: current_business.owner?(current_user),
      meta: {
        filter: team_name_filter,
        page: page,
        pageSize: page_size,
        sortOption: sort_option,
        orderOption: order_option
      },
    }
  end

  private

  sig { params(params: ActionController::Parameters).returns(T::Hash[Symbol, T.untyped]) }
  def validate_team_org_params(params)
    result = { error: "", selected_organization_ids: [] }

    unless BusinessTeam.organization_selection_types.keys.include?(params[:organizationSelectionType])
      result[:valid] = false
      result[:error] = "Invalid organization selection type."
      return result
    end

    begin
      result[:selected_organization_ids] = JSON.parse(params[:selectedOrganizationIds] || "[]").map(&:to_i)
    rescue JSON::ParserError
      result[:valid] = false
      result[:error] = "Invalid JSON format for selectedOrganizationIds"
    end

    result
  end

  sig { params(team: BusinessTeam, business: Business).returns(T::Hash[Symbol, T.untyped]) }
  def team_payload(team, business)
    {
      name: team.name,
      id: team.id,
      memberCount: team.member_ids.count,
      slug: team.slug,
      description: team.description,
      viewTeamUrl: enterprise_team_path(business.slug, team.slug, only_path: true),
      editTeamUrl: edit_enterprise_team_path(business.slug, team.slug, only_path: true),
    }
  end

  sig { params(name: String, old_team_slug: T.nilable(String)).void }
  def business_team_name_check(name, old_team_slug) # rubocop:todo GitHub/UseRestfulActions
    if name.blank?
      return render json: { team: name, error: "name cannot be empty" }, status: 422
    end
    slug = name.parameterize

    # Name has an emoji
    unless GitHub::UTF8.valid_unicode3?(name)
      return render json: { team: name, error: "contains unsupported characters" }, status: 422
    end

    # Name has not been modified
    if old_team_slug && old_team_slug == slug
      return render json: { message: "unchanged" }
    end

    # Name is already used.
    if current_business.business_teams.find_by(name: name) || current_business.business_teams.find_by(slug: slug)
      return render json: { team: name, error: "is already taken" }, status: 422
    end

    render json: { team: name }
  end

  sig { params(query: T.nilable(String), ids: T.nilable(T::Array[Integer])).void }
  def organization_suggestions(query, ids)
    query = query&.strip&.downcase
    scope = current_business.organizations.includes(:profile)
    scope = scope.where.not(id: ids) if ids.present?
    total_available_count = scope.count
    scope = scope.where(["users.login LIKE :q OR profiles.name LIKE :q", {
      q: "%#{ActiveRecord::Base.sanitize_sql_like(query)}%",
    }]) if query.present?
    scope = scope.references(:profile)
    scope = scope.order(Arel.sql("COALESCE(profiles.name, users.display_login)")).limit(PER_PAGE)
    organizations = scope.map { |organization| organization_payload(organization) }
    render(json: { organizations: organizations, totalAvailableCount: total_available_count })
  end

  sig { params(organization: T.untyped).returns(T::Hash[T.untyped, T.untyped]) }
  def organization_payload(organization)
    {
      name: organization.profile_name || organization.display_login,
      id: organization.id,
      avatarUrl: organization.primary_avatar_url,
      description: organization.description
    }
  end
end

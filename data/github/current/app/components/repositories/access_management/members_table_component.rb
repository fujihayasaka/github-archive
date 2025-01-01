# typed: strict
# frozen_string_literal: true

class Repositories::AccessManagement::MembersTableComponent < ApplicationComponent
  sig { returns(Repository) }
  attr_reader :repository

  sig { returns(EditRepositories::Pages::ManagedAccessPageView) }
  attr_reader :view

  sig { params(view: EditRepositories::Pages::ManagedAccessPageView).void }
  def initialize(view:)
    @view = view
    @repository = T.let(view.repository, Repository)
  end

  sig { override.returns(T::Boolean) }
  def render?
    actors_with_organization_access.present?
  end

  sig { returns(T.nilable(Integer)) }
  memoize def filtered_role_id
    params[:role_id]&.to_i
  end

  sig { returns(T.nilable(String)) }
  memoize def search_query
    params[:org_search].presence
  end

  sig { returns(T::Array[T.untyped]) }
  def paginated_teams
    paginated_members[:teams].map do |data|
      team = T.let(data[:team], Team)
      description = "@#{team.name_with_display_owner} • #{pluralize(team.members_count, 'member')}"
      role_name = display_name(data[:role_name].to_s)
      [team, description, role_name]
    end
  end

  sig { returns(T::Array[T.untyped]) }
  def paginated_users
    paginated_members[:users].map do |data|
      role_name = display_name(data[:role_name].to_s)

      [data[:user], role_name]
    end
  end

  private

  sig { returns(Symbol) }
  def selected_tab
    return :organization if params[:tab] == "organization" || view.direct_access_headcount == 0

    :direct
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def teams_with_organization_access
    T.must(actors_with_organization_access["Team"]).select do |data|
      next if filtered_role_id && !data[:role_ids].include?(filtered_role_id)

      team = T.let(data[:team], Team)
      next if search_query && team.name&.downcase&.exclude?(T.must(search_query).downcase)
      true
    end
  end

  sig { returns(T::Array[T.untyped]) }
  memoize def users_with_organization_access
    T.must(actors_with_organization_access["User"]).select do |data|
      next if filtered_role_id && !data[:role_ids].include?(filtered_role_id)

      user = T.let(data[:user], User)
      next if search_query && user.name.downcase.exclude?(T.must(search_query).downcase)
      true
    end
  end

  sig { returns(T::Hash[String, T::Array[T.untyped]]) }
  memoize def actors_with_organization_access
    view.organization_wide_access_list
  end

  sig { returns(String) }
  def organization_access_total_label
    case params[:type]
    when "team"
      count = teams_with_organization_access.count
      pluralize(count, "team")
    when "user"
      count = users_with_organization_access.count
      pluralize(count, "user")
    else
      count = teams_with_organization_access.count + users_with_organization_access.count
      pluralize(count, "actor")
    end
  end

  sig { params(query_params: T.untyped).returns(String) }
  def ram_page_path(query_params)
    repository_access_management_path(repository.owner, repository, role_id: params[:role_id], type: params[:type], **query_params)
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  memoize def paginated_members
    total_items = teams_with_organization_access.size + users_with_organization_access.size
    total_pages = (total_items.to_f / limit).ceil

    offset = (page - 1) * limit
    current_page_teams = teams_with_organization_access[offset, limit] || []
    remaining_items = limit - current_page_teams.size
    user_offset = [offset - teams_with_organization_access.size, 0].max
    current_page_users = users_with_organization_access[user_offset, remaining_items] || []
    { teams: current_page_teams, users: current_page_users }
  end

  sig { returns(T::Boolean) }
  def has_previous_page?
    page > 1
  end

  sig { returns(T::Boolean) }
  def has_next_page?
    total_items = teams_with_organization_access.size + users_with_organization_access.size
    total_pages = (total_items.to_f / limit).ceil
    page < total_pages
  end

  sig { returns(Integer) }
  def page
    params[:page]&.to_i || 1
  end

  sig { returns(Integer) }
  def limit
    10
  end

  sig { returns(T::Boolean) }
  def has_organization_based_actors?
    case params[:type]
    when "team"
      teams_with_organization_access.any?
    when "user"
      users_with_organization_access.any?
    else
      users_with_organization_access.any? || teams_with_organization_access.any?
    end
  end

  sig { params(role_name: String).returns(String) }
  def display_name(role_name)
    role_name_sym = role_name.to_sym
    if OrganizationRole::SYSTEM_ROLE_METADATA.keys.include?(role_name_sym)
      role_data = T.must(OrganizationRole::SYSTEM_ROLE_METADATA[role_name_sym])
      role_data[:display_name] || role_name
    else
      role_name
    end
  end
end

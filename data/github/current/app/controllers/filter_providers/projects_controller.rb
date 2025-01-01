# typed: strict
# frozen_string_literal: true

class FilterProviders::ProjectsController < FilterProvidersController
  include FilterProviders::RepositoriesDependency

  depends_on_clusters ApplicationRecord::Configurations,
    ApplicationRecord::Memex,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Collab

  depends_on_clusters ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::IamAbilities, only: [:show]

  MEMEX_PROJECT_LIMIT = 100
  OWNER_LIMIT = 25

  sig { void }
  def index
    respond_payload({ projects: find_projects.map { |p| format_response(p) } })
  end

  sig { void }
  def show
    if project_from_query.present?
      respond_payload(format_response(T.must(project_from_query)))
    else
      head :unprocessable_entity
    end
  end

  private

  sig { returns(T::Array[MemexProject]) }
  def find_projects
    return [] unless GitHub.projects_new_enabled?

    owner_ids = owner_ids_for_context

    return [] if !logged_in? && !has_repository_context?

    # Limit the project search to just the owner from the query if it's present,
    # but make sure repo context takes precedence.
    owners = if owner_from_query.present? && !has_repository_context?
      [T.must(owner_from_query)]
    else
      User.where(id: owner_ids).limit(OWNER_LIMIT).to_a
    end

    # We only need initial suggestions if there is no search query, pre-fetch it now to avoid a race condition in the promises.
    initial_suggestion_rankings = has_search_query? ? [] : recently_visited_project_ids(owner_ids)

    projects = owners.map do |owner|
      # Preload the association to owner to avoid a polymorphic association error 'EagerLoadPolymorphicError'
      scope = owner.memex_projects.active_projects.open_projects.preload(:owner).where("title IS NOT NULL")

      if has_search_query?
        # If search query starts with '{org}/' or is a number then we want to filter by number
        project_number = query_value.start_with?("#{owner.display_login}/") ? query_value.split("/").last : query_value

        if project_number.match?(/\A\d+\z/)
          # Since title is a VARBINARY column, we ordinarily cannot compare a value to it using LIKE.
          # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
          scope = scope.where(
            "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) LIKE ? OR CAST(number AS CHAR CHARACTER SET utf8mb4) LIKE ?",
            MemexProject::DEFAULT_TITLE,
            like_query_value,
            "%#{project_number}%"
          )
        elsif owner_from_query.nil?
          # Since title is a VARBINARY column, we ordinarily cannot compare a value to it using LIKE.
          # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
          scope = scope.where(
            "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) LIKE ?",
            MemexProject::DEFAULT_TITLE,
            "#{like_query_value}"
          )
        end
      else
        scope.where(id: initial_suggestion_rankings)
      end

      scope = scope.limit(MEMEX_PROJECT_LIMIT)
      owner.accessible_memexes_scope(scope, current_user)
    end.flatten.uniq

    sort_projects(projects, owner_ids).take(maximum_result_limit)
  end

  sig { returns(T.nilable(MemexProject)) }
  memoize def project_from_query
    return nil unless query_value.include?("/")
    return nil unless (owner_from_query = self.owner_from_query)

    project_number = query_value.split("/").last
    return nil unless project_number.match?(/\A\d+\z/)
    # Preload the association to owner to avoid a polymorphic association error 'EagerLoadPolymorphicError'
    owner_from_query.accessible_memexes_scope(
      owner_from_query.memex_projects.preload(:owner).where(number: project_number),
      current_user
    ).first
  end

  sig { returns(T.nilable(T.any(Organization, User))) }
  memoize def owner_from_query
    return nil unless query_value.include?("/")
    login = query_value.split("/").first
    User.find_by_login(login)
  end

  sig { returns(T::Array[Integer]) }
  memoize def owner_ids_for_context
    if repositories_for_context.any?
      repositories_for_context.map(&:owner_id).uniq
    elsif owner_from_query.present?
      [owner_from_query&.id]
    elsif current_user
      [current_user.id]
    else
      []
    end
  end

  sig { params(owner_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def recently_visited_project_ids(owner_ids = [])
    # If we have a search query, we will go via the `recently_visited_project_ids_for_given_projects` pathway
    return [] if has_search_query?
    return [] unless (current_user = self.current_user)

    scope = MemexProjectVisit.where(viewer_id: current_user.id)
    scope = scope.where(owner_id: owner_ids) if owner_ids.present?
    scope.order(last_visited_at: :desc).limit(MEMEX_PROJECT_LIMIT).pluck(:memex_project_id)
  end

  sig { params(filter_ids: T::Array[T.nilable(Integer)]).returns(T::Array[Integer]) }
  def recently_visited_project_ids_for_given_projects(filter_ids)
    return [] if filter_ids.empty?
    return [] unless (current_user = self.current_user)

    MemexProjectVisit
      .where(memex_project_id: filter_ids, viewer_id: current_user.id)
      .order(last_visited_at: :desc)
      .limit(maximum_result_limit)
      .pluck(:memex_project_id)
  end

  sig { params(projects: T::Array[MemexProject], owner_ids: T::Array[Integer]).returns(T::Array[MemexProject]) }
  def sort_projects(projects, owner_ids)
    return projects if projects.empty?

    # Prioritize projects that have been visited by the current user, in order of most recently visited.
    # Then prioritize projects that start with the search query; then alphabetically as a tiebreaker.
    project_rankings = {}

    if has_search_query?
      recently_visited_project_ids_for_given_projects(projects.map(&:id))
    else
      recently_visited_project_ids(owner_ids)
    end.each_with_index.map { |project_id, ranking| project_rankings[project_id] = ranking.to_s }

    not_visited_value = "100000" # An arbitrarily large value to use for projects that have not been visited.

    sorted_projects = projects.sort_by do |project|
      [
        project_rankings.key?(project.id) ? project_rankings[project.id] : not_visited_value,
        project.display_title.start_with?(query_value) ? "0" : "1",
        project.display_title
      ]
    end

    sorted_projects
  end

  sig { params(project: MemexProject).returns(T::Hash[Symbol, T.untyped]) }
  def format_response(project)
    {
      title: project.title,
      value: "#{project.owner.display_login}/#{project.number}"
    }
  end

  sig { returns(T.untyped) }
  def resource_for_conditional_access
    # returning the controller to use tfca for functions where we either
    # don't have a project, or actions don't need a project so we can
    # find the potential owner of the query
    return self unless action_name == "show"
    return self if project_from_query.nil?
    project_from_query
  end

  sig { returns(T.untyped) }
  def target_for_conditional_access
    owner_from_query || current_user || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end
end

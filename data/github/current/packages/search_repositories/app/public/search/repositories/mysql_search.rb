# typed: strict
# frozen_string_literal: true

module Search::Repositories::MysqlSearch
  SUPPORTED_TERMS = %i(
    fork
    visibility
    archived
    mirror
    template
    sort
  ).freeze

  SUPPORTED_SORTS = %w(
    name name-asc
    stargazers
    stars stars-desc
    updated updated-desc
  ).freeze

  # Do not support more than 2 terms to prevent a very complex MySQL query.
  # 2 is the maximum number of terms needed for existing types
  MAX_TERMS = 2

  sig { params(query: T.nilable(String), user: T.nilable(User)).returns(T::Boolean) }
  def self.supported?(query, user)
    return true if query.blank?

    parsed_query = ::Search::Queries::RepoQuery.coerce(query, user)

    return false if parsed_query.size > MAX_TERMS

    parsed_query.all? do |component|
      next false unless component.is_a?(Array)
      key, value, negated = component
      supported_term?(key, value, negated)
    end
  end

  sig { params(key: Symbol, value: T.any(String, T::Array[T.untyped]), negated: T.nilable(T::Boolean)).returns(T::Boolean) }
  private_class_method def self.supported_term?(key, value, negated)
    return false if negated
    return false unless SUPPORTED_TERMS.include?(key)
    return false if value.is_a?(Array)
    return false if key == :sort && !GitHub.flipper[:es_repos_mysql_support_sort].enabled?
    return false if key == :sort && !SUPPORTED_SORTS.include?(value)
    true
  end

  ReposSearchResult = T.type_alias do
    {
      repos: T::Array[Repository],
      total: Integer,
      total_pages: Integer,
    }
  end

  INCLUDE_TABLES = T.let(%i(
    internal_repository
    mirror
    network
    repository_license
  ).freeze, T::Array[Symbol])

  PRELOAD_TABLES = T.let(%i(
    owner
    primary_language
  ).freeze, T::Array[Symbol])

  sig do
    params(
      org: ::Organization,
      user: T.nilable(User),
      q: T.nilable(String),
      page: Integer,
      per_page: Integer,
      sort_order: T.nilable(String),
      limit_to_repo_ids: T.nilable(T::Array[Integer]),
    ).returns(ReposSearchResult)
  end
  def self.search(org, user, q, page, per_page:, sort_order:, limit_to_repo_ids:)
    raise ArgumentError, "Query not supported" unless supported?(q, user)

    repos = GitHub.dogstats.distribution_time("repos_list.search_org_repos.time", tags: ["engine:mysql"]) do
      results = org.visible_repositories_for(user).where(owner_id: org)
      results = results.includes(INCLUDE_TABLES).preload(PRELOAD_TABLES)

      parsed_query = ::Search::Queries::RepoQuery.coerce(q.downcase, user) if q.present?
      results = filter_repos_by_query(results, parsed_query) if parsed_query.present?
      results = filter_repos_by_ids(results, limit_to_repo_ids:)

      results = case compute_sort_order(parsed_query, sort_order)
      when "name", "name-asc"
        results.sorted_by_name
      when "stars", "stars-desc", "stargazers"
        results.most_starred
      else
        results.recently_updated
      end

      results.paginate(page: page, per_page: per_page).to_a
    end

    GitHub.dogstats.distribution("repos_list.search_org_repos.total", repos.total_entries, tags: ["engine:mysql"])

    {
      repos: repos,
      total: repos.total_entries,
      total_pages: repos.total_pages,
    }
  end

  # Internal: Given a query, it will return a modified scope that filters the
  # repositories according to the modifiers present on the parsed query.
  sig { params(repos: T.untyped, parsed_query: T::Array[[Symbol, String]]).returns(T.untyped) }
  def self.filter_repos_by_query(repos, parsed_query)
    parsed_query.inject(repos) do |scope, component|
      key, value = component
      case key
      when :fork
        filter_repos_by_fork(scope, value:)
      when :visibility
        filter_repos_by_visibility(scope, value:)
      when :archived
        filter_repos_by_archived(scope, value:)
      when :mirror
        filter_repos_by_mirror(scope, value:)
      when :template
        filter_repos_by_template(scope, value:)
      else
        scope
      end
    end
  end

  # Internal: Returns a modified scope filtered by the given fork value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def self.filter_repos_by_fork(repos, value:)
    case value
    when "true"  then repos.forks
    when "false"
      repos
        # No index is applied when "parent_id IS NULL" for some reason, so we force it to avoid a slow query
        # Limited to this query as others have different WHERE clauses and may perform better with another index
        .from("repositories FORCE INDEX (index_repositories_on_owner_and_parent_and_public_and_source_id)")
        .where(parent_id: nil)
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given visibility.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def self.filter_repos_by_visibility(repos, value:)
    case value
    when "public"   then repos.public_scope
    when "private"  then repos.private_not_internal_scope
    when "internal" then repos.internal_scope
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given archived value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def self.filter_repos_by_archived(repos, value:)
    case value
    when "true"  then repos.archived_scope
    when "false" then repos.not_archived_scope
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given mirror value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def self.filter_repos_by_mirror(repos, value:)
    case value
    when "true"  then repos.joins(:mirror)
    when "false" then repos.left_outer_joins(:mirror).where(mirrors: { id: nil })
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given template value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def self.filter_repos_by_template(repos, value:)
    case value
    when "true"  then repos.templates
    when "false" then repos.where(template: false)
    else repos
    end
  end

  # Internal: Given a Repository scope, will return a modified scope that filters the
  # repositories according to the given IDs. The given IDs will be limited to the first 10,000 values.
  sig { params(repos: T.untyped, limit_to_repo_ids: T.nilable(T::Array[Integer])).returns(T.untyped) }
  def self.filter_repos_by_ids(repos, limit_to_repo_ids:)
    limit_to_repo_ids.present? ? repos.where(id: limit_to_repo_ids) : repos
  end

  sig { params(parsed_query: T.nilable(T::Array[[Symbol, String]]), sort_order: T.nilable(String)).returns(T.nilable(String)) }
  def self.compute_sort_order(parsed_query, sort_order)
    return sort_order unless parsed_query.present?

    sort_component = parsed_query.find { |key, _| key == :sort }
    _, value = sort_component
    value || sort_order
  end
end

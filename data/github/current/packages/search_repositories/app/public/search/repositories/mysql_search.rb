# typed: strict
# frozen_string_literal: true

class Search::Repositories::MysqlSearch
  include GitHub::Memoizer

  OWNER_TERMS = %i(owner org user).freeze

  SUPPORTED_TERMS = T.let(%i(
    fork
    visibility
    archived
    mirror
    template
    sort
    contributed-by
  ).concat(OWNER_TERMS).freeze, T::Array[Symbol])

  SUPPORTED_SORTS = %w(
    name-asc
    stargazers
    stars stars-desc
    updated updated-desc
    relevance
  ).freeze

  # Do not support more than 2 terms to prevent a very complex MySQL query.
  # 2 is the maximum number of terms needed for existing types
  MAX_TERMS = 2

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
      user: T.nilable(User),
      query: T.nilable(String),
      page: Integer,
      scope: Search::Repositories::ScopeType,
      per_page: Integer,
      sort_order: T.nilable(String),
      cap_filter: T.nilable(ConditionalAccess::Filter),
      limit_to_repo_ids: T.nilable(T::Array[Integer]),
      allow_contributed_by_filter: T::Boolean,
      support_single_owner_in_mysql: T::Boolean,
    ).void
  end
  def initialize(user, query, page = 1, scope: nil, per_page: 10, sort_order: nil, cap_filter: nil, limit_to_repo_ids: nil, allow_contributed_by_filter: false, support_single_owner_in_mysql: false)
    @user = user
    @query = query
    @page = page
    @scope = scope
    @per_page = per_page
    @sort_order = sort_order
    @cap_filter = cap_filter
    @limit_to_repo_ids = limit_to_repo_ids
    @allow_contributed_by_filter = allow_contributed_by_filter
    @support_single_owner_in_mysql = support_single_owner_in_mysql
  end

  sig { returns(T::Boolean) }
  def supported?
    return @scope.present? if @query.blank?

    return false unless scoped_query?

    # If limit_to_repo_ids has more than 10K elements, we do not support the query
    # We want to avoid passing too many IDs to a MySQL query.
    return false if @limit_to_repo_ids&.size.to_i > Search::Repositories::MAX_LIMIT_TO_REPO_IDS

    return false if parsed_query.size > MAX_TERMS

    parsed_query.all? do |component|
      next false unless component.is_a?(Array)
      key, value, negated = component
      supported_term?(key, value, negated)
    end
  end

  sig { returns(Search::Repositories::ReposSearchResult) }
  def search
    raise ArgumentError, "Query not supported" unless supported?
    repos = GitHub.dogstats.distribution_time("repos_list.search_org_repos.time", tags: ["engine:mysql"]) do
      results = repos_source
      results = results.includes(INCLUDE_TABLES).preload(PRELOAD_TABLES)

      results = filter_repos_by_query(results) if parsed_query.present?
      results = filter_repos_by_ids(results, limit_to_repo_ids: @limit_to_repo_ids)

      sort_and_paginate(results, @user, compute_sort_order)
    end

    GitHub.dogstats.distribution("repos_list.search_org_repos.total", repos.total_entries, tags: ["engine:mysql"])

    {
      repos: repos,
      total: repos.total_entries,
      total_pages: repos.total_pages,
    }
  end

  private

  sig { params(key: Symbol, value: T.any(String, T::Array[T.untyped]), negated: T.nilable(T::Boolean)).returns(T::Boolean) }
  def supported_term?(key, value, negated)
    return false if negated
    return false unless SUPPORTED_TERMS.include?(key)
    return false if value.is_a?(Array)
    return false if key == :sort && !FeatureFlag.vexi.enabled_or_raise?(:es_repos_mysql_support_sort) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
    return false if key == :sort && !SUPPORTED_SORTS.include?(value)
    # Relevance sort can only be applied by MySQL with the contributed repos,
    # because it's done in memory after pagination.
    return false if key == :sort && value == "relevance" && !has_contributed_by_filter?
    return false if OWNER_TERMS.include?(key) && !@support_single_owner_in_mysql
    return false if OWNER_TERMS.include?(key) && single_owner.nil?
    true
  end

  sig { returns(T::Array[[Symbol, String]]) }
  memoize def parsed_query
    return [] unless @query.present?

    ::Search::Queries::RepoQuery.coerce(@query.downcase, @user)
  end

  sig { returns(T::Boolean) }
  def scoped_query?
    @scope.present? || has_contributed_by_filter? || single_owner.present?
  end

  sig { returns(T::Boolean) }
  def has_contributed_by_filter?
    @allow_contributed_by_filter && parsed_query.include?([:'contributed-by', "@me"])
  end

  sig { returns(T.nilable(User)) }
  memoize def single_owner
    return nil unless query_owners.size == 1

    return @scope[:org] if @scope.present?

    first_login = query_owners.first
    return @user if first_login == "@me"

    User.find_by(login: first_login)
  end

  sig { returns(T::Array[String]) }
  def query_owners
    owners = parsed_query.filter_map do |component|
      key, value = component
      next unless OWNER_TERMS.include?(key)

      value.split(",")
    end.flatten

    owners.append(@scope[:org].display_login) if @scope.present?

    owners.uniq
  end

  # Internal: Returns the repositories initial scope from the org or from the contributed-by (or both combined).
  sig { returns(T.untyped) }
  def repos_source
    if @user.present? && has_contributed_by_filter?
      # We need a query instead of a materialized array because we need to preload other tables, sort and paginate.
      contributed_repos = Repository.where(id: contributed_repo_ids)

      if single_owner.present?
        contributed_repos.where(owner_id: single_owner)
      else
        contributed_repos
      end
    else
      return Repository.none unless single_owner.present?

      T.must(single_owner).visible_repositories_for(@user)&.where(owner_id: single_owner)
    end
  end

  sig { returns(T.untyped) }
  def contributed_repo_ids
    return [] unless @user.present?

    repos = @user.repositories_contributed_to(
      viewer: @user,
      limit: 100,
      exclude_owned: false,
      since: 1.year.ago,
    )

    return repos.pluck(:id) unless @cap_filter.present?
    @cap_filter.authorized_resource_ids(repos)
  end

  # Internal: Given a query, it will return a modified scope that filters the
  # repositories according to the modifiers present on the parsed query.
  sig { params(repos: T.untyped).returns(T.untyped) }
  def filter_repos_by_query(repos)
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
  def filter_repos_by_fork(repos, value:)
    case value
    when "true"  then repos.forks
    when "false"
      if @scope
        # No index is applied when "parent_id IS NULL" for some reason, so we force it to avoid a slow query
        # Limited to this query from org (@scope) as others have different WHERE clauses and may perform better with another index
        repos = repos.from("repositories FORCE INDEX (index_repositories_on_owner_and_parent_and_public_and_source_id)")
      end
      repos.where(parent_id: nil)
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given visibility.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def filter_repos_by_visibility(repos, value:)
    case value
    when "public"   then repos.public_scope
    when "private"  then repos.private_not_internal_scope
    when "internal" then repos.internal_scope
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given archived value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def filter_repos_by_archived(repos, value:)
    case value
    when "true"  then repos.archived_scope
    when "false" then repos.not_archived_scope
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given mirror value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def filter_repos_by_mirror(repos, value:)
    case value
    when "true"  then repos.joins(:mirror)
    when "false" then repos.left_outer_joins(:mirror).where(mirrors: { id: nil })
    else repos
    end
  end

  # Internal: Returns a modified scope filtered by the given template value.
  sig { params(repos: T.untyped, value: String).returns(T.untyped) }
  def filter_repos_by_template(repos, value:)
    case value
    when "true"  then repos.templates
    when "false" then repos.where(template: false)
    else repos
    end
  end

  # Internal: Given a Repository scope, will return a modified scope that filters the
  # repositories according to the given IDs. The given IDs will be limited to the first 10,000 values.
  sig { params(repos: T.untyped, limit_to_repo_ids: T.nilable(T::Array[Integer])).returns(T.untyped) }
  def filter_repos_by_ids(repos, limit_to_repo_ids:)
    limit_to_repo_ids.present? ? repos.where(id: limit_to_repo_ids) : repos
  end

  sig { returns(T.nilable(String)) }
  def compute_sort_order
    return @sort_order unless parsed_query.present?

    sort_component = parsed_query.find { |key, _| key == :sort }
    _, value = sort_component
    value || @sort_order
  end

  sig { params(results: T.untyped, user: T.nilable(User), sort_order: T.nilable(String)).returns(T.untyped) }
  def sort_and_paginate(results, user, sort_order)
    results = case sort_order
    when "name-asc"
      results.sorted_by_name
    when "stars", "stars-desc", "stargazers"
      results.most_starred
    else
      results.recently_updated_by_id
    end

    results = results.paginate(page: @page, per_page: @per_page).to_a

    # relevance sorting can only be applied efficiently in memory
    if user.present? && sort_order == "relevance"
      sorted_ids = contributed_repo_ids
      results.sort_by! { |repo| sorted_ids.index(repo.id) || Float::INFINITY }
    end

    results
  end
end

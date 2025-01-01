# typed: strict
# frozen_string_literal: true

module Search::Repositories::EsSearch
  extend self
  include Scientist

  sig do
    params(
      user: T.nilable(User),
      q: T.nilable(String),
      page: Integer,
      scope: Search::Repositories::ScopeType,
      per_page: Integer,
      sort_order: T.nilable(String),
      user_session: T.nilable(UserSession),
      cap_filter: T.nilable(ConditionalAccess::Filter),
      limit_to_repo_ids: T.nilable(T::Array[Integer]),
      allow_contributed_by_filter: T::Boolean,
      experiment_unbounded: T::Boolean,
    ).returns(Search::Repositories::ReposSearchResult)
  end
  def search(user, q, page, scope:, per_page:, sort_order:, user_session:, cap_filter:, limit_to_repo_ids:, allow_contributed_by_filter: false, experiment_unbounded: false)
    kwargs = { per_page:, sort_order:, user_session:, limit_to_repo_ids:, allow_contributed_by_filter:, experiment_unbounded: }

    search = execute_es_query(user, q, page, scope:, cap_filter:, **kwargs)

    GitHub.dogstats.distribution("repos_list.search_org_repos.total", search.total, tags: ["engine:es"])

    {
      repos: search.results.map { |r| r["_model"] },
      total: search.total,
      total_pages: search.total_pages,
    }
  end

  sig do
    params(
      user: T.nilable(GitHub::IFlipperActor),
      q: T.nilable(String),
      page: T.untyped,
      scope: Search::Repositories::ScopeType,
      per_page: T.untyped,
      sort_order: T.nilable(String),
      user_session: T.untyped,
      cap_filter: T.untyped,
      limit_to_repo_ids: T.untyped,
      experiment_owner_id_and_repo_id: T::Boolean,
      experiment_unbounded: T::Boolean,
      allow_contributed_by_filter: T::Boolean,
    ).returns(Search::Results[T.untyped])
  end
  def execute_es_query(user, q, page, scope: nil, per_page: Repository.per_page, sort_order: nil, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil, experiment_owner_id_and_repo_id: false, experiment_unbounded: false, allow_contributed_by_filter: false)
    GitHub.dogstats.distribution_time("repos_list.search_org_repos.time", tags: ["engine:es"]) do
      query = Search::Queries::RepoQuery.new(
        current_user: user,
        phrase: q,
        max_offset: 10_000,
        page: page,
        # RepoQuery defaults to sort by stars, but on the org page we want to default to last updated
        sort: (search_sort(sort_order) unless q&.include?("sort:")),
        per_page: per_page,
        user_session:,
        cap_filter:,
        include_forks: true,
        binary_fork_filter: true,
        visibility_and_execution: true,
        preload_tables: Search::Repositories::MysqlSearch::PRELOAD_TABLES + Search::Repositories::MysqlSearch::INCLUDE_TABLES + [:network_privilege],
        limit_to_repo_ids:,
        experiment_owner_id_and_repo_id:,
        experiment_unbounded:,
        allow_contributed_by_filter:,
      )

      org = scope&.dig(:org)

      if org.present?
        query.qualifiers[:org].clear.must org.display_login
        query.qualifiers[:user].clear
        query.qualifiers[:owner].clear
        query.qualifiers[:repo].clear
      end

      query.execute
    end
  end

  sig { params(order_by: T.nilable(String)).returns(T::Array[String]) }
  def search_sort(order_by)
    case order_by
    when "name"
      %w(name asc)
    when "stargazers"
      %w(stars desc)
    when "relevance"
      %w(relevance desc)
    else
      %w(updated desc)
    end
  end
end

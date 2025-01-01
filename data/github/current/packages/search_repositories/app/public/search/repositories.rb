# typed: strict
# frozen_string_literal: true

module Search::Repositories

  MAX_LIMIT_TO_REPO_IDS = 10_000

  ScopeType = T.type_alias { T.any(NilClass, { org: ::Organization }) }

  sig do
    params(
      user: T.nilable(User),
      q: T.nilable(String),
      page: Integer,
      scope: ScopeType,
      per_page: Integer,
      sort_order: T.nilable(String),
      user_session: T.nilable(UserSession),
      cap_filter: T.nilable(ConditionalAccess::Filter),
      limit_to_repo_ids: T.nilable(T::Array[Integer]),
      allow_contributed_by_filter: T::Boolean,
      support_single_owner_in_mysql: T::Boolean,
      experiment_unbounded: T::Boolean,
    ).returns(ReposSearchResult)
  end
  def self.search_repos(user, q, page, scope: nil, per_page: Repository.per_page, sort_order: nil, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil, allow_contributed_by_filter: false, support_single_owner_in_mysql: false, experiment_unbounded: false)
    return { repos: [], total: 0, total_pages: 0 } if !limit_to_repo_ids.nil? && limit_to_repo_ids.empty?

    common_kwargs = { scope: scope, per_page:, sort_order:, limit_to_repo_ids:, cap_filter:, allow_contributed_by_filter: }
    mysql_search = MysqlSearch.new(user, q, page, support_single_owner_in_mysql:, **common_kwargs)
    if mysql_search.supported?
      mysql_search.search
    else
      EsSearch.search(user, q, page, user_session:, experiment_unbounded:, **common_kwargs)
    end
  end

  ReposSearchResult = T.type_alias do
    {
      repos: T::Array[Repository],
      total: Integer,
      total_pages: Integer,
    }
  end
end

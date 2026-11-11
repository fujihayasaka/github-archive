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
      experiment_unbounded: T::Boolean,
    ).returns(ReposSearchResult)
  end
  def self.search_repos(user, q, page, scope: nil, per_page: Repository.per_page, sort_order: nil, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil, experiment_unbounded: false)
    return { repos: [], total: 0, total_pages: 0, error_message: nil } if !limit_to_repo_ids.nil? && limit_to_repo_ids.empty?

    common_kwargs = { scope: scope, per_page:, sort_order:, limit_to_repo_ids:, cap_filter: }
    mysql_search = MysqlSearch.new(user, q, page, **common_kwargs)
    if mysql_search.supported?
      mysql_search.search
    else
      EsSearch.search(user, q, page, user_session:, experiment_unbounded:, **common_kwargs)
    end
  end

  # Get the common properties source for a list of organizations
  # - If a single organization, that's the source
  # - If multiple organizations, the common business if they share one
  # - Otherwise nil as there's no common source
  #
  sig { params(logins: T::Array[String]).returns(T.any(Business, Organization, NilClass)) }
  def self.get_common_source(logins)
    return nil if logins.empty?

    return Organization.find_by(login: logins.first) if logins.size == 1

    business_ids = Organization.where(login: logins)
      .left_joins(:business_membership)
      .group("business_organization_memberships.business_id")
      .limit(2) # We only need 2 groups to check whether we have a single business
      .pluck("business_organization_memberships.business_id")

    Business.find_by(id: business_ids.first) if business_ids.size == 1
  end

  ReposSearchResult = T.type_alias do
    {
      repos: T::Array[Repository],
      total: Integer,
      total_pages: Integer,
      error_message: T.nilable(String),
    }
  end
end

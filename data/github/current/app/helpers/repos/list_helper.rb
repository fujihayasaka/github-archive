# typed: strict
# frozen_string_literal: true

module Repos::ListHelper
  extend T::Helpers
  extend T::Sig
  include ::Search::Repositories

  requires_ancestor { Kernel }

  sig do
    params(
      org: ::Organization,
      user: T.nilable(User),
      q: T.nilable(String),
      page: Integer,
      per_page: Integer,
      sort_order: T.nilable(String),
      user_session: T.nilable(UserSession),
      cap_filter: T.nilable(ConditionalAccess::Filter),
      limit_to_repo_ids: T.nilable(T::Array[Integer]),
    ).returns(MysqlSearch::ReposSearchResult)
  end
  def search_org_repos(org, user, q, page, per_page: Repository.per_page, sort_order: nil, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil)
    if !limit_to_repo_ids.nil?
      raise ArgumentError, "limit_to_repo_ids must not contain more than 10,000 ids" if limit_to_repo_ids.size > 10_000
      return { repos: [], total: 0, total_pages: 0 } if limit_to_repo_ids.empty?
    end

    common_kwargs = { per_page:, sort_order:, limit_to_repo_ids: }
    if MysqlSearch.supported?(q, user)
      MysqlSearch.search(org, user, q, page, **common_kwargs)
    else
      EsSearch.search(org, user, q, page, user_session:, cap_filter:, **common_kwargs)
    end
  end
end

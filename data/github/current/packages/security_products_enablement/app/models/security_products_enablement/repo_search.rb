# typed: true
# frozen_string_literal: true

module SecurityProductsEnablement
  module RepoSearch
    extend Repos::ListHelper

    sig do
      params(
        query: String,
        organization: ::Organization,
        actor: User,
        user_session: T.nilable(UserSession),
        cap_filter: T.nilable(ConditionalAccess::Filter),
        current_page: Integer,
        per_page: Integer,
        repository_ids: T.nilable(T::Array[Integer])
      ).returns(Search::Repositories::MysqlSearch::ReposSearchResult)
    end
    def self.fetch_repos(query:, organization:, actor:, user_session:, cap_filter:, current_page:, per_page:, repository_ids: nil)
      GitHub.dogstats.distribution_time("security_products_enablement.repo_search.fetch_repos.time") do
        query_parser = build_query_parser(organization, query)
        limit_to_repo_ids, search_results_limit_exceeded = execute_mysql_filters(query_parser:, organization:, actor:, user_session:)

        search_repos(
          organization,
          actor,
          query_parser.es_query_string,
          current_page,
          per_page:,
          user_session:,
          cap_filter:,
          limit_to_repo_ids: limit_to_repo_ids || repository_ids,
          repo_ids_limit_exceeded: search_results_limit_exceeded,
        )
      end
    end

    sig do
      params(
        query: String,
        organization: ::Organization,
        actor: User,
        user_session: T.nilable(UserSession),
        cap_filter: T.nilable(ConditionalAccess::Filter),
        per_page: Integer,
        blk: T.nilable(T.proc.params(repository_id: Integer).void)
      ).returns(T::Array[Integer])
    end
    def self.find_repo_ids_with_offset_pagination(query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk)
      query_parser = build_query_parser(organization, query)
      limit_to_repo_ids, search_results_limit_exceeded = execute_mysql_filters(query_parser:, organization:, actor:, user_session:)

      repo_ids = []
      current_page = 0 # Start at 0 because we'll add 1 in the search loop.

      # Fake query_result which will be updated as we search, type-defined so Sorbet lets us update it in the loop:
      query_result = T.let(
        { repos: [], total: 0, total_pages: 1 },
        { repos: T::Array[::Repository], total: Integer, total_pages: Integer }
      )

      iterations = 0
      while current_page < query_result[:total_pages]
        current_page += 1

        query_result = search_repos(
          organization,
          actor,
          query_parser.es_query_string,
          current_page,
          limit_to_repo_ids:,
          per_page:,
          user_session:,
          cap_filter:,
          repo_ids_limit_exceeded: search_results_limit_exceeded,
        )

        repo_ids.concat query_result[:repos].collect(&:id)

        if block_given?
          query_result[:repos].each do |repo|
            yield repo.id
          end
        end

        iterations += 1
      end
      GitHub.dogstats.distribution("find_repo_ids_by_query.iterations", iterations, tags: ["cursor_pagination:false", "per_page:#{per_page}"])

      repo_ids
    end

    sig do
      params(
        query: String,
        organization: ::Organization,
        actor: User,
        user_session: T.nilable(UserSession),
        cap_filter: T.nilable(ConditionalAccess::Filter),
        per_page: Integer,
        blk: T.nilable(T.proc.params(repository_id: Integer).void)
      ).returns(T::Array[Integer])
    end
    def self.find_repo_ids_with_cursor_pagination(query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk)
      query_parser = build_query_parser(organization, query)
      limit_to_repo_ids, search_results_limit_exceeded = execute_mysql_filters(query_parser:, organization:, actor:, user_session:)

      repo_ids = []
      after_cursor = T.let(nil, T.nilable(String))
      has_next_page = T.let(true, T::Boolean)

      iterations = 0
      while has_next_page
        search = execute_cursor_paginated_es_query(
          organization,
          actor,
          query_parser.es_query_string,
          per_page:,
          user_session:,
          cap_filter:,
          limit_to_repo_ids:,
          after_cursor:
        )

        ids = search.results.map { |r| r["_model"].id }
        ids.each { |repo_id| yield repo_id } if block_given?

        repo_ids.concat ids
        after_cursor = search.end_cursor
        has_next_page = search.has_next_page
        iterations += 1
      end
      GitHub.dogstats.distribution("find_repo_ids_by_query.iterations", iterations, tags: ["cursor_pagination:true", "per_page:#{per_page}"])

      repo_ids
    end

    sig do
      params(
        org: ::Organization,
        user: T.nilable(GitHub::IFlipperActor),
        q: T.nilable(String),
        per_page: T.untyped,
        user_session: T.untyped,
        cap_filter: T.untyped,
        limit_to_repo_ids: T.untyped,
        before_cursor: T.nilable(String),
        after_cursor: T.nilable(String),
      ).returns(Search::Responses::CursorPaginationResponse)
    end
    def self.execute_cursor_paginated_es_query(org, user, q, per_page: ::Repository.per_page, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil, before_cursor: nil, after_cursor: nil)
      query = Search::Queries::CursorPaginatedRepoQuery.new(
        current_user: user,
        phrase: q,
        sort: (%w(updated desc) unless q&.include?("sort:")),
        per_page:,
        user_session:,
        cap_filter:,
        include_forks: true,
        binary_fork_filter: true,
        preload_tables: Search::Repositories::MysqlSearch::PRELOAD_TABLES + Search::Repositories::MysqlSearch::INCLUDE_TABLES + [:network_privilege],
        limit_to_repo_ids:,
        before: before_cursor,
        after: after_cursor,
        skip_permission_check: user.is_a?(Bot), # Bots can't see private repos, so skip permission check to allow them to see private repos in the org.
      )

      query.qualifiers[:org].clear.must org.display_login
      query.qualifiers[:user].clear
      query.qualifiers[:owner].clear
      query.qualifiers[:repo].clear

      query.execute
    end

    sig do
      params(organization: Organization, search_query: String).returns(Search::Queries::SecurityConfigurations::RepositoryQuery)
    end
    def self.build_query_parser(organization, search_query)
      Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query, include_archived_repos: true)
    end

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
        repo_ids_limit_exceeded: T::Boolean,
      ).returns(Search::Repositories::MysqlSearch::ReposSearchResult)
    end
    def self.search_repos(org, user, q, page, per_page: ::Repository.per_page, sort_order: nil, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil, repo_ids_limit_exceeded: false)
      # The search_org_repos helper will decide whether to use MySQL or ES based on the given search query.
      # When repo_ids_limit_exceeded is true, it means that the limit_to_repo_ids array has more than 10K elements.
      # We will specifically use ES to execute the query in this case to avoid potentially passing too many IDs to a MySQL query.
      if repo_ids_limit_exceeded
        Search::Repositories::EsSearch.search(org, user, q, page, per_page:, sort_order:, user_session:, cap_filter:, limit_to_repo_ids:)
      else
        search_org_repos(org, user, q, page, per_page:, sort_order:, user_session:, cap_filter:, limit_to_repo_ids:)
      end
    end


    sig do
      params(
        query_parser: Search::Queries::SecurityConfigurations::RepositoryQuery,
        organization: Organization,
        actor: User,
        user_session: T.nilable(UserSession),
      ).returns([T.nilable(T::Array[Integer]), T::Boolean])
    end
    def self.execute_mysql_filters(query_parser:, organization:, actor:, user_session: nil)
      return [nil, false] unless query_parser.mysql_query_hash.present?
      SecurityProductsEnablement::ListReposQuery.new(org: organization, user: actor, filter_hash: query_parser.mysql_query_hash, user_session:).repository_ids
    end
  end
end

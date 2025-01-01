# typed: true
# frozen_string_literal: true

module Settings
  module SecurityProducts
    module RepositoriesHelper
      extend T::Sig
      include GitHub::Memoizer
      include Repos::ListHelper

      SECURITY_FEATURES = [:SECRET_SCANNING, :CODE_SCANNING, :SECRET_SCANNING_PUSH_PROTECTION, :DEPENDABOT_ALERTS, :ADVANCED_SECURITY]
      DEFAULT_PER_PAGE = 25

      sig do
        params(
          organization: ::Organization,
          user: User,
          user_session: UserSession,
          cap_filter: T.nilable(ConditionalAccess::Filter),
          search_query: String,
          current_page: Integer,
          per_page: Integer,
          repository_ids: T.nilable(T::Array[Integer])
        ).returns(T::Hash[Symbol, T.untyped])
      end
      def serialized_repositories(organization:, user:, user_session:, cap_filter:, search_query: "", current_page: 1, per_page: DEFAULT_PER_PAGE, repository_ids: nil)
        GitHub.logger.info("searching for repos",
          "gh.security_products_enablement.query": search_query,
          "gh.actor.id": user.id,
          "gh.organization.id": organization.id,
          "code.namespace": self.class.name,
          "code.function": __method__,
        )

        query_parser = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query: search_query)

        limit_to_repo_ids = nil
        search_results_limit_exceeded = false
        if query_parser.mysql_query_hash.present?
          limit_to_repo_ids, search_results_limit_exceeded = SecurityProductsEnablement::ListReposQuery.new(
            org: organization, user: user, filter_hash: query_parser.mysql_query_hash
          ).repository_ids
        end

        # Filter repositories by repository_ids if provided
        query_result = search_org_repos(
          organization,
          user,
          query_parser.es_query_string,
          current_page,
          per_page:,
          user_session:,
          cap_filter:,
          limit_to_repo_ids: limit_to_repo_ids || repository_ids
        )

        repositories = query_result[:repos]
        repository_security_configurations =
          RepositorySecurityConfiguration.where(repository_id: repositories.map(&:id)).includes(:security_configuration)

        # Validate that GHAS has been purchased before finding license info. If not, don't bother.
        if organization.advanced_security_purchased?
          licenses_retrieved, repository_licenses_required = licenses_required_for_repositories(repositories)
        else
          licenses_retrieved, repository_licenses_required = false, {}
        end

        repositories_payload = repositories.map do |repository|
          payload = {
            id: repository.id,
            name: repository.name,
            visibility: repository.visibility,
            pushed_at: repository.pushed_at || repository.created_at,
            licenses_required: repository_licenses_required[repository.id] || (licenses_retrieved ? 0 : nil),
          }

          repo_security_config = repository_security_configurations.where(repository_id: repository.id).first
          security_config_payload = if repo_security_config
            {
              name: T.must(repo_security_config.security_configuration).name,
              status: repo_security_config.state,
              failure_reason: repo_security_config.failure_reason,
              is_github_recommended_configuration: T.must(repo_security_config.security_configuration).is_github_recommended_configuration?,
              repository_security_configuration_id: repo_security_config.id,
            }
          end

          payload.merge({
            security_configuration: security_config_payload || nil,
            security_features_enabled: security_config_payload.blank? ? security_features_enabled?(repository) : false,
          })
        end

        {
          repositories: repositories_payload,
          total_repository_count: query_result[:total],
          page_count: query_result[:total_pages],
          search_results_limit_exceeded:
        }
      end

      sig { params(repository: Repository).returns(T::Boolean) }
      def security_features_enabled?(repository)
        SecurityProduct::DependencyGraph.new(repository).enabled? ||
        SecurityProduct::PrivateVulnerabilityReporting.new(repository).enabled? ||
        SECURITY_FEATURES.any? { |feature| repository.security_feature_configured?(feature) }
      end

      sig { params(repositories: T::Array[Repository]).returns([T::Boolean, T::Hash[Integer, Integer]]) }
      def licenses_required_for_repositories(repositories)
        return false, {} unless repositories.present?

        owner = T.must(repositories.first).owner
        repository_ids = repositories.map { |r| T.must(r.id) }
        begin
          results = AdvancedSecurityLicense.new(T.must(owner)).additional_committers_per_repository(repository_ids:)
          [true, results]
        rescue => e # rubocop:todo Lint/GenericRescue
          Failbot.report(e)
          [false, {}]
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
          use_cursor_pagination: T::Boolean,
          blk: T.nilable(T.proc.params(repository_id: Integer).void)
        ).returns(T::Array[Integer])
      end
      def find_repo_ids_by_query(query:, organization:, actor:, user_session:, cap_filter:, per_page: 100, use_cursor_pagination: false, &blk)
        GitHub.logger.info("searching for repos",
          "gh.security_products_enablement.query": query,
          "gh.security_products_enablement.use_cursor_pagination": use_cursor_pagination,
          "gh.actor.id": actor.id,
          "gh.organization.id": organization.id,
          "code.namespace": self.class.name,
          "code.function": __method__,
        )

        GitHub.dogstats.distribution_time("find_repo_ids_by_query.time", tags: ["cursor_pagination:#{use_cursor_pagination}", "per_page:#{per_page}"]) do
          if use_cursor_pagination
            find_repo_ids_by_query_v2(query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk)
          else
            find_repo_ids_by_query_v1(query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk)
          end
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
      def find_repo_ids_by_query_v1(query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk)
        query_parser = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

        limit_to_repo_ids = nil
        if query_parser.mysql_query_hash.present?
          limit_to_repo_ids, _ = SecurityProductsEnablement::ListReposQuery.new(
            org: organization, user: actor, filter_hash: query_parser.mysql_query_hash
          ).repository_ids
        end

        repo_ids = []
        current_page = 0 # Start at 0 because we'll add 1 in the search loop.

        # Fake query_result which will be updated as we search, type-defined so Sorbet lets us update it in the loop:
        query_result = T.let(
          { repos: [], total: 0, total_pages: 1 },
          { repos: T::Array[Repository], total: Integer, total_pages: Integer }
        )

        iterations = 0
        while current_page < query_result[:total_pages]
          current_page += 1

          query_result = search_org_repos(
            organization,
            actor,
            query_parser.es_query_string,
            current_page,
            limit_to_repo_ids:,
            per_page: 100,
            user_session:,
            cap_filter:,
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
      def find_repo_ids_by_query_v2(query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk)
        query_parser = Search::Queries::SecurityConfigurations::RepositoryQuery.new(query:)

        limit_to_repo_ids = nil
        if query_parser.mysql_query_hash.present?
          limit_to_repo_ids, _ = SecurityProductsEnablement::ListReposQuery.new(
            org: organization, user: actor, filter_hash: query_parser.mysql_query_hash
          ).repository_ids
        end

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
      def execute_cursor_paginated_es_query(org, user, q, per_page: Repository.per_page, user_session: nil, cap_filter: nil, limit_to_repo_ids: nil, before_cursor: nil, after_cursor: nil)
        query = Search::Queries::CursorPaginatedRepoQuery.new(
          current_user: user,
          phrase: q,
          sort: (%w(updated desc) unless q&.include?("sort:")),
          per_page:,
          user_session:,
          cap_filter:,
          include_forks: true,
          binary_fork_filter: true,
          preload_tables: MysqlSearch::PRELOAD_TABLES + MysqlSearch::INCLUDE_TABLES + [:network_privilege],
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
    end
  end
end

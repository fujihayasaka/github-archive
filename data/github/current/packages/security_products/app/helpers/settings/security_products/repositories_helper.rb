# typed: true
# frozen_string_literal: true

module Settings
  module SecurityProducts
    module RepositoriesHelper
      extend T::Helpers

      requires_ancestor { Kernel }

      SECURITY_FEATURES = [:SECRET_SCANNING, :CODE_SCANNING, :SECRET_SCANNING_PUSH_PROTECTION, :DEPENDABOT_ALERTS, :ADVANCED_SECURITY]
      DEFAULT_PER_PAGE = 25

      sig do
        params(
          organization: T.nilable(::Organization),
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
          "gh.organization.id": organization&.id || nil,
          "code.namespace": self.class.name,
          "code.function": __method__,
        )

        if organization
          query_result = SecurityProductsEnablement::RepoSearch.fetch_repos(
            query: search_query, organization:, actor: user, user_session:, cap_filter:, current_page:, per_page:, repository_ids:
          )

          repositories = query_result[:repos]
        else
          repositories = Repository.where(owner_id: user.id)
        end
        repository_security_configurations =
          RepositorySecurityConfiguration.where(repository_id: repositories.map(&:id)).includes(:security_configuration)

        # Validate that GHAS has been purchased before finding license info. If not, don't bother.
        if organization&.advanced_security_purchased?
          licenses_retrieved, repository_licenses_required = licenses_required_for_repositories(repositories)
        else
          licenses_retrieved, repository_licenses_required = false, {}
        end

        repositories_payload = repositories.map do |repository|
          payload = {
            id: repository.id,
            name: repository.name,
            visibility: repository.visibility,
            archived: repository.archived?,
            pushed_at: repository.pushed_at || repository.created_at,
            licenses_required: repository_licenses_required[repository.id] || (licenses_retrieved ? 0 : nil),
          }

          repo_security_config = repository_security_configurations.detect { |rsc| rsc.repository_id == repository.id }
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

        if organization
          total_repository_count = query_result[:total]
          page_count = query_result[:total_pages]
        else
          total_repository_count = repositories.count
          page_count = (total_repository_count.to_f / per_page).ceil
        end

        {
          repositories: repositories_payload,
          total_repository_count:,
          page_count:,
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

        tags = ["cursor_pagination:#{use_cursor_pagination}", "per_page:#{per_page}"]
        GitHub.dogstats.distribution_time("find_repo_ids_by_query.time", tags:) do
          if use_cursor_pagination
            SecurityProductsEnablement::RepoSearch.find_repo_ids_with_cursor_pagination(
              query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk
            )
          else
            SecurityProductsEnablement::RepoSearch.find_repo_ids_with_offset_pagination(
              query:, organization:, actor:, user_session:, cap_filter:, per_page:, &blk
            )
          end
        end
      end
    end
  end
end

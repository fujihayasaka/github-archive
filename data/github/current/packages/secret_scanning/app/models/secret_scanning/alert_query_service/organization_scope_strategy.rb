# typed: true
# frozen_string_literal: true

module SecretScanning
  class AlertQueryService

    class OrganizationScopeStrategy < ScopeStrategy
      include SecretScanning::Features::FeatureFlagHelper

      REPO_IDS_SIZE_LIMIT = 10000 # The maximum number of repository IDs we're willing to send to the API in a single request

      sig { returns(User) }
      attr_reader :user

      sig { returns(T.nilable(UserSession)) }
      attr_reader :user_session

      sig { returns(Organization) }
      attr_reader :organization

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :allowed_repository_ids

      sig { returns(Search::Queries::SecurityCenter::SecretScanningQuery) }
      attr_reader :parsed_query

      sig do
        params(
          user: User,
          user_session: T.nilable(UserSession),
          organization: Organization,
          parsed_query: Search::Queries::SecurityCenter::SecretScanningQuery,
          allowed_repository_ids: T.nilable(T::Array[Integer])
        ).void
      end
      def initialize(user:, user_session:, organization:, parsed_query:, allowed_repository_ids: nil)
        @user = user
        @user_session = user_session
        @organization = organization
        @parsed_query = parsed_query
        @allowed_repository_ids = allowed_repository_ids
      end

      ##
      # @see ScopeStrategy#with_selector!
      def with_selector!(request_hash, aggregation_filter: nil)
        # early exit in case the user doesn't have access to any repositories
        raise InvalidQueryError if allowed_repository_ids && allowed_repository_ids.blank?

        request_hash[:org_selector] = GitHub::Proto::SecretScanning::Api::V2::OrgSelector.new(
          owner_id: organization.id,
          repository_ids: allowed_repository_ids,
          repos_are_excluded: false,
          repository_visibilities: GitHub::TokenScanning::SecretScanningHelper::ALL_PROTO_REPO_VISIBILITIES,
        )

        with_repos!(request_hash, aggregation_filter)
        cap_repos!(request_hash)
      end

      ##
      # @see ScopeStrategy#with_feature_flags!
      def with_feature_flags!(request_hash)
        request_hash[:feature_flags].concat get_tokens_api_feature_flags(organization)
      end

      ##
      # @see ScopeStrategy#tenant_filter_scope
      def tenant_filter_scope
        GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(:organization, organization, "secret_scanning")
      end

      ##
      # @see ScopeStrategy#map_filter_options
      def map_filter_options(filter, aggregation)
        case filter
        when SecretScanningControllerHelper::GroupByAggregation::REPOSITORY
          map_repository_aggregation_counts(aggregation)
        else
          raise ArgumentError, "Unsupported aggregation type #{filter}"
        end
      end

      ##
      # @see ScopeStrategy#show_custom_patterns?
      def show_custom_patterns?
        SecretScanning::Features::Org::CustomPatterns.new(organization).feature_available?
      end

      private

      # We cap the number of repo IDs to what we believe we can safely send to the service to avoid "runaway" numbers
      # of repos (from filters like topic and team) that might cause errors in the service.
      def cap_repos!(request_hash)
        repo_ids_size = request_hash[:org_selector].repository_ids&.size || -1

        if repo_ids_size > REPO_IDS_SIZE_LIMIT
          request_hash[:org_selector].repository_ids.slice!(0...REPO_IDS_SIZE_LIMIT)

          log_warn(
            "Repo ID limit surpassed: #{repo_ids_size}",
            "gh.security_products.feature_type": "secret-scanning",
            "gh.org.id": organization.id,
            "gh.org.login": organization.display_login,
            "gh.security_products.search.query": parsed_query.query,
          )
        end

        GitHub.dogstats.distribution(
          "security_center.alert_query_service.repo_ids_count.dist",
          repo_ids_size,
          tags: [
            "scope:org",
            "feature:secret-scanning",
            "filter-mode:#{request_hash[:org_selector].repos_are_excluded ? "exclusive" : "inclusive"}",
            "exceeds-limit:#{repo_ids_size > REPO_IDS_SIZE_LIMIT}",
          ],
        )
      end

      def with_repos!(request_hash, aggregation_filter)
        inputs = {}.tap do |hsh|
          hsh[:names] = [parsed_query.repository_names, parsed_query.negated_repository_names] unless aggregation_filter == SecretScanningControllerHelper::GroupByAggregation::REPOSITORY
          hsh[:teams] = [parsed_query.team_names, parsed_query.negated_team_names]
          hsh[:topics] = [parsed_query.topics, parsed_query.negated_topics]
          hsh[:custom_properties] = parsed_query.custom_properties_query_string
        end

        filters = ::SecurityCenter::FilterMappers::ToRepositoryIds.new(
          ::SecurityCenter::FilterMappers::ToRepositoryIds::InputFilters.new(**inputs),
          repo_ids_scope: allowed_repository_ids,
          orgs: [organization],
          user: user,
          user_session: user_session,
        ).to_filters

        raise InvalidQueryError if filters == ::SecurityCenter::FilterMappers::ToRepositoryIds::FALSE_FILTERS

        incl_filters, excl_filters = filters
        return unless incl_filters.present? || excl_filters.present?

        # Check net values for repo filter. Return early if there are conflicting values.
        if incl_filters.present?
          # [what you can see] & [what you want to see] - [what you don't want to see]
          net_include = incl_filters - excl_filters
          request_hash[:org_selector].repository_ids.clear.concat(net_include)
          request_hash[:org_selector].repos_are_excluded = false
        elsif excl_filters.present?
          net_exclude = excl_filters - incl_filters
          request_hash[:org_selector].repository_ids.clear.concat(net_exclude)
          request_hash[:org_selector].repos_are_excluded = true
        end

        raise InvalidQueryError if request_hash[:org_selector].repository_ids.empty?
      end

      def selected_repo_ids
        @selected_repo_ids ||= filtered_repo_ids(parsed_query.repository_names)
      end

      def negated_repo_ids
        @negated_repo_ids ||= filtered_repo_ids(parsed_query.negated_repository_names)
      end

      def filtered_repo_ids(repo_names)
        return [] if repo_names.empty?
        organization.repositories.where(name: repo_names).pluck(:id)
      end

      ##
      # Map the `RepoTokenCountAggregation` to a format that can be used by the frontend.
      def map_repository_aggregation_counts(repo_aggregation)
        repo_ids = repo_aggregation.counts.map(&:repository_id)
        repos_by_id = Repository.select(:id, :name, :owner_login).where(id: repo_ids).index_by(&:id)

        items = repo_aggregation.counts.
          select { |o| repos_by_id.key?(o.repository_id) }.
          map do |obj|
            repo = repos_by_id[obj.repository_id]
            item_count = AlertQueryService.filter_count_by_state(obj.unresolved_count, obj.resolved_count, parsed_query)

            {
              count: item_count,
              label: repo.name,
              slug: repo.name.downcase,
            }
          end

        [[{ items: SecurityCenterHelper.sort_items_with_counts(items) }], false]
      end
    end

  end
end

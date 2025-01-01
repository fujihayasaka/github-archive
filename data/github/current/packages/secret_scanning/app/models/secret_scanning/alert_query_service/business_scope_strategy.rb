# typed: true
# frozen_string_literal: true

module SecretScanning
  class AlertQueryService

    class BusinessScopeStrategy < ScopeStrategy
      include GitHub::Memoizer
      include SecretScanning::Features::FeatureFlagHelper

      REPO_IDS_SIZE_LIMIT = OrganizationScopeStrategy::REPO_IDS_SIZE_LIMIT # The maximum number of repository IDs we're willing to send to the API in a single request

      sig { returns(User) }
      attr_reader :user

      sig { returns(UserSession) }
      attr_reader :user_session

      sig { returns(Business) }
      attr_reader :business

      sig { returns(T.any(T::Array[Organization], ActiveRecord::Relation)) }
      attr_reader :organizations

      sig { returns(Search::Queries::SecurityCenter::SecretScanningQuery) }
      attr_reader :parsed_query

      sig do
        params(
          user: User,
          user_session: UserSession,
          business: Business,
          organizations: T.any(T::Array[Organization], ActiveRecord::Relation),
          parsed_query: Search::Queries::SecurityCenter::SecretScanningQuery
        ).void
      end
      def initialize(user:, user_session:, business:, organizations:, parsed_query:)
        @user = user
        @user_session = user_session
        @business = business
        @organizations = organizations
        @parsed_query = parsed_query
      end

      ##
      # @see ScopeStrategy#with_selector!
      def with_selector!(request_hash, aggregation_filter: nil)
        request_hash[:business_selector] = GitHub::Proto::SecretScanning::Api::V2::BusinessSelector.new(
          id: business.id,
          organization_ids: authorized_org_ids,
          repository_visibilities: GitHub::TokenScanning::SecretScanningHelper::ALL_PROTO_REPO_VISIBILITIES,
          user_ids: [],
          user_filter: :NONE,
          owner_types: [],
          excluded_owner_types: [],
        )

        with_owners!(request_hash, aggregation_filter)
        with_owner_types!(request_hash)
        with_repos!(request_hash, aggregation_filter)
        cap_repos!(request_hash)
        restrict_requested_users!(request_hash)
      end

      ##
      # @see ScopeStrategy#with_feature_flags!
      def with_feature_flags!(request_hash)
        request_hash[:feature_flags].concat get_tokens_api_feature_flags(business)
      end

      ##
      # @see ScopeStrategy#tenant_filter_scope
      def tenant_filter_scope
        GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(:business, business, "secret_scanning")
      end

      ##
      # @see ScopeStrategy#map_filter_options
      def map_filter_options(filter, aggregation)
        case filter
        when SecretScanningControllerHelper::GroupByAggregation::OWNER
          map_owner_aggregation_counts(aggregation)
        when SecretScanningControllerHelper::GroupByAggregation::REPOSITORY
          map_repository_aggregation_counts(aggregation)
        else
          raise ArgumentError, "Unsupported aggregation type #{filter}"
        end
      end

      ##
      # @see ScopeStrategy#show_custom_patterns?
      def show_custom_patterns?
        SecretScanning::Features::Business::CustomPatterns.new(business).feature_available?
      end

      private

      memoize def include_emus?
        AdvancedSecurity::Features::Business::AdvancedSecurity.new(business).feature_available_for_user_repositories?
      end

      # We cap the number of repo IDs to what we believe we can safely send to the service to avoid "runaway" numbers
      # of repos (from filters like topic and team) that might cause errors in the service.
      def cap_repos!(request_hash)
        repo_ids_size = request_hash[:business_selector].repository_ids&.size || -1

        if repo_ids_size > REPO_IDS_SIZE_LIMIT
          request_hash[:business_selector].repository_ids.slice!(0...REPO_IDS_SIZE_LIMIT)

          log_warn(
            "Repo ID limit surpassed: #{repo_ids_size}",
            "gh.security_products.feature_type": "secret-scanning",
            "gh.business.id": business.id,
            "gh.business.name": business.name,
            "gh.security_products.search.query": parsed_query.query,
          )
        end

        GitHub.dogstats.distribution(
          "security_center.alert_query_service.repo_ids_count.dist",
          repo_ids_size,
          tags: [
            "scope:business",
            "feature:secret-scanning",
            "filter-mode:#{request_hash[:business_selector].repos_are_excluded ? "exclusive" : "inclusive"}",
            "exceeds-limit:#{repo_ids_size > REPO_IDS_SIZE_LIMIT}",
          ],
        )
      end

      def authorized_org_ids
        @authorized_org_ids = organizations.map(&:id)
      end

      def with_owner_types!(request_hash)
        return unless parsed_query.owner_types_enums.present? || parsed_query.negated_owner_types_enums.present?

        # Check net values for resolution filter. Return early if there are conflicting values.
        included, excluded = net_qualifier_values(parsed_query.owner_types_enums, parsed_query.negated_owner_types_enums).values_at(:included, :excluded)
        raise InvalidQueryError if included.blank? && excluded.blank?

        request_hash[:business_selector].owner_types.clear.concat(included)
        request_hash[:business_selector].excluded_owner_types.clear.concat(excluded)
      end

      def with_owners!(request_hash, aggregation_filter)
        request_hash[:business_selector].user_filter = :ALL if include_emus?

        # Do not modify the user filter or organization_ids any further if
        # the aggregation is owner. Get everything
        return if aggregation_filter == SecretScanningControllerHelper::GroupByAggregation::OWNER

        return unless parsed_query.owners.present? || parsed_query.negated_owners.present?

        if parsed_query.owners.present?
          net_owners = parsed_query.owners - parsed_query.negated_owners
          net_org_ids = filtered_org_ids(net_owners)
          net_user_ids = filtered_user_ids(net_owners)

          request_hash[:business_selector].organization_ids.clear.concat(net_org_ids)
          request_hash[:business_selector].user_ids.clear.concat(net_user_ids)
          request_hash[:business_selector].user_filter = net_user_ids.empty? ? :NONE : :ONLY
        elsif parsed_query.negated_owners.present?
          exclude_org_ids = filtered_org_ids(parsed_query.negated_owners)
          exclude_user_ids = filtered_user_ids(parsed_query.negated_owners)

          net_org_ids = authorized_org_ids - exclude_org_ids
          request_hash[:business_selector].organization_ids.clear.concat(net_org_ids)

          request_hash[:business_selector].user_ids.clear.concat(exclude_user_ids)
          request_hash[:business_selector].user_filter = exclude_user_ids.empty? ? :ALL : :EXCEPT
        end

        if include_emus?
          raise InvalidQueryError if
            request_hash[:business_selector].user_ids.empty? &&
            request_hash[:business_selector].user_filter == :NONE &&
            request_hash[:business_selector].organization_ids.empty?
        else
          raise InvalidQueryError if request_hash[:business_selector].organization_ids.empty?
        end
      end

      def with_repos!(request_hash, aggregation_filter)
        inputs = {}.tap do |hsh|
          hsh[:names] = [parsed_query.repository_names, parsed_query.negated_repository_names] unless aggregation_filter == SecretScanningControllerHelper::GroupByAggregation::REPOSITORY
          hsh[:teams] = [parsed_query.team_names, parsed_query.negated_team_names]
          hsh[:topics] = [parsed_query.topics, parsed_query.negated_topics]
        end

        repo_filters = ::SecurityCenter::FilterMappers::ToRepositoryIds.new(
          ::SecurityCenter::FilterMappers::ToRepositoryIds::InputFilters.new(**inputs),
          repo_ids_scope: nil,
          orgs: organizations.to_a,
          user: user,
          user_session: user_session,
          scope: @business,
        ).to_filters

        raise InvalidQueryError if repo_filters == ::SecurityCenter::FilterMappers::ToRepositoryIds::FALSE_FILTERS

        incl_filters, excl_filters = repo_filters
        return unless incl_filters.present? || excl_filters.present?

        net_repo_ids(request_hash, incl_filters, excl_filters)

        # Return early if there are conflicting values.
        raise InvalidQueryError if request_hash[:business_selector].repository_ids.empty?
      end

      ##
      # This method is present in the event that the user is not an owner of the business
      # It's not a problem for organizations, since the authorized orgs we get passed in
      # at the beginning comes from CAP filtering.
      # For users, we need to modify the request hash to the best we can to only include
      # results for the current user
      def restrict_requested_users!(request_hash)
        # Only go down this codepath if we have a user filter
        return if request_hash[:business_selector].user_filter == :NONE

        # Do nothing if the current user is a business owner
        return if SecurityProduct::Permissions::BusinessAuthz.new(business, actor: user).can_view_user_owned_repository_alerts?

        # When using a negative filter, only allow themselves to exclude their own alerts
        # This effectively will return 0 alerts. Is there a way to
        # short-circuit the entire network call?
        # We can only be sure they would be 0 results, if authorized orgs is empty too
        if request_hash[:business_selector].user_filter == :EXCEPT
          # If they were trying to exclude themselves, then we'll just return 0 user results
          if (request_hash[:business_selector].user_ids & [user.id]).any?
            request_hash[:business_selector].user_ids.clear
            request_hash[:business_selector].user_filter = :NONE
            return
          end
        end

        # Otherwise, restrict the user filter to only the current user
        request_hash[:business_selector].user_ids.clear.concat([user.id])
        request_hash[:business_selector].user_filter = :ONLY
      end

      def net_repo_ids(request_hash, incl_ids, excl_ids)
        if incl_ids.present?
          # [what you can see] & [what you want to see] - [what you don't want to see]
          net_include = incl_ids - excl_ids
          request_hash[:business_selector].repository_ids.clear.concat(net_include)
          request_hash[:business_selector].repos_are_excluded = false
        elsif excl_ids.present?
          net_exclude = excl_ids - incl_ids
          request_hash[:business_selector].repository_ids.clear.concat(net_exclude)
          request_hash[:business_selector].repos_are_excluded = true
        end
      end

      def filtered_org_ids(org_names)
        return [] if org_names.empty?

        # If we're filtering by orgs, we need to confirm they are both in the enterprise, and available to the user,
        # so intersect with the set of orgs the user has access to.
        Organization.with_logins(org_names).pluck(:id) & authorized_org_ids
      end

      def filtered_user_ids(usernames)
        feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business)
        return [] if usernames.empty?
        return [] unless include_emus?

        # Start from User table
        selected_user_ids = User
          .where(type: "User", login: usernames)
          .compact
          .map(&:id)

        # Filter against business
        feature
          .get_enterprise_users(user_ids: selected_user_ids)
          .map(&:id)
      end

      def map_user_aggregation_counts(repo_aggregation)
        raise ArgumentError, "Expected RepoTokenCountAggregation" unless repo_aggregation.instance_of?(GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation)
        repo_ids = repo_aggregation.counts.map(&:repository_id)

        repo_and_owner_ids = Repository.where(id: repo_ids).pluck([:id, :owner_id])
        repo_owner_ids = repo_and_owner_ids.map { |item| item[1] }
        repos_by_owner = repo_and_owner_ids.group_by { |item| item[1] }
          .transform_values { |items| items.map { |item| item[0] } }

        owners = User.where(id: repo_owner_ids, type: "USER").pluck([:id, :display_login])

        items = []
        owners.each do |(owner_id, login)|
          repo_ids = repos_by_owner[owner_id]
          agg_items = repo_aggregation.counts.
            select { |o| repo_ids.include?(o.repository_id) }

          count = AlertQueryService.filter_count_by_state(agg_items.sum(&:unresolved_count), agg_items.sum(&:resolved_count), parsed_query)
          items << {
            count: count,
            description: "User",
            label: login,
            slug: login.downcase,
          }
        end

        [[{ items: SecurityCenterHelper.sort_items_with_counts(items) }], false]
      end

      ##
      # Map the `RepoTokenCountAggregation` to a format that can be used by the frontend.
      def map_organization_aggregation_counts(repo_aggregation)
        raise ArgumentError, "Expected RepoTokenCountAggregation" unless repo_aggregation.instance_of?(GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation)
        repo_ids = repo_aggregation.counts.map(&:repository_id)

        # Post-apply filter by selected_repositories
        # In enterprise view, `selected_repositories` will be "org/repo" format.
        if parsed_query.repository_names.present?
          selected_repository_ids = RepositorySecurityCenterConfig.
            includes(:repository).
            select(:repository_id).
            where(repository_id: repo_ids).
            select { |c| parsed_query.repository_names.include?(c.repository&.name_with_display_owner.downcase) }.
            map(&:repository_id)
          repo_ids &= selected_repository_ids
        end

        org_repos = RepositorySecurityCenterConfig.
          select(:owner_id, :repository_id).
          where(repository_id: repo_ids)

        items = business.organizations.
          map do |org|
            # get repo_ids for org
            org_repo_ids = org_repos.
              select { |rsc| rsc.owner_id == org.id }.
              map { |rsc| rsc.repository_id }

            # get repo aggregate items for org
            agg_items = repo_aggregation.counts.
              select { |o| org_repo_ids.include?(o.repository_id) }

            {
              count: AlertQueryService.filter_count_by_state(agg_items.sum(&:unresolved_count), agg_items.sum(&:resolved_count), parsed_query),
              description: "Organization",
              label: org.display_login,
              slug: org.display_login.downcase
            }
          end

        [[{ items: SecurityCenterHelper.sort_items_with_counts(items) }], false]
      end

      ##
      # Map the `OwnerTokenCountAggregation` to a format that can be used by the frontend.
      def map_owner_aggregation_counts(repo_aggregation)
        orgs = map_organization_aggregation_counts(repo_aggregation)[0][0][:items]

        users = []
        feature = AdvancedSecurity::Features::Business::AdvancedSecurity.new(business)
        users = map_user_aggregation_counts(repo_aggregation)[0][0][:items] if feature.feature_available_for_user_repositories?

        [[{ items: SecurityCenterHelper.sort_items_with_counts(orgs + users) }], false]
      end

      ##
      # Map the `RepoTokenCountAggregation` to a format that can be used by the frontend.
      def map_repository_aggregation_counts(repo_aggregation)
        raise ArgumentError, "Expected RepoTokenCountAggregation" unless repo_aggregation.instance_of?(GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation)
        repo_ids = repo_aggregation.counts.map(&:repository_id)
        repos_by_id = Repository.select(:id, :name, :owner_login).
          where(id: repo_ids).
          select do |r|

            parsed_query.owners.empty? || parsed_query.owners.include?(r.owner_display_login.downcase)
          end.
          index_by(&:id)

        items = repo_aggregation.counts.
          select { |o| repos_by_id.key?(o.repository_id) }.
          map do |obj|
            repo = repos_by_id[obj.repository_id]
            item_count = AlertQueryService.filter_count_by_state(obj.unresolved_count, obj.resolved_count, parsed_query)

            {
              count: item_count,
              label: repo.name,
              description: repo.owner_display_login,
              slug: repo.name_with_display_owner.downcase
            }
          end

        [[{ items: SecurityCenterHelper.sort_items_with_counts(items) }], false]
      end

      def net_qualifier_values(selected, negated)
        # Examples
        #   provider:a                see provider a
        #   -provider:a               see everything but provider a
        #   provider:a -provider:a    see nothing
        #   provider:a -provider:b    see provider a
        #   provider:a -provider:a,b  see nothing
        #   provider:a,b -provider:b  see provider a

        if selected.present?
          net_include = selected - negated
          { included: net_include, excluded: [] }
        elsif negated.present?
          net_exclude = negated - selected
          { included: [], excluded: net_exclude }
        else
          { included: [], excluded: [] }
        end
      end
    end

  end
end

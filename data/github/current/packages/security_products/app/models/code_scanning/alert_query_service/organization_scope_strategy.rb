# typed: true
# frozen_string_literal: true

module CodeScanning
  class AlertQueryService
    class OrganizationScopeStrategy < ScopeStrategy
      TenantFilteringHelper = GitHub::SecurityCenter::TenantFilteringHelper

      sig { returns(User) }
      attr_reader :user

      sig { returns(T.nilable(UserSession)) }
      attr_reader :user_session

      sig { returns(Organization) }
      attr_reader :organization

      sig { returns(Search::Queries::SecurityCenter::CodeScanningOrgQuery) }
      attr_reader :parsed_query

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :allowed_repository_ids

      sig do
        params(
          user: User,
          user_session: T.nilable(UserSession),
          organization: Organization,
          parsed_query: Search::Queries::SecurityCenter::CodeScanningOrgQuery,
          allowed_repository_ids: T.nilable(T::Array[Integer])
        ).void
      end
      def initialize(user:, user_session:, organization:, parsed_query:, allowed_repository_ids: nil)
        @user = user
        @user_session = user_session
        @allowed_repository_ids = allowed_repository_ids
        @organization = organization
        @parsed_query = parsed_query
      end

      memoize def scope
        :organization
      end

      sig { returns(TenantFilteringHelper::RequestScope) }
      memoize def tenant_filter_scope
        TenantFilteringHelper::RequestScope.new(
          :organization,
          organization,
          ::SecurityCenter::SecurityFeatures::CODE_SCANNING
        )
      end

      memoize def tenant_id
        @organization.id
      end

      memoize def tenant_name
        @organization.name
      end

      def with_owner_ids!(hash)
        hash[:owner_ids] = [organization.id]
      end

      def with_repository_ids!(hash, exclude_filter_type: nil)
        inputs = {}.tap do |h|
          h[:names] = [parsed_query.repository_names, parsed_query.excluded_repository_names] unless exclude_filter_type == :repo
          h[:teams] = [parsed_query.team_names, parsed_query.excluded_team_names]
          h[:topics] = [parsed_query.topics, parsed_query.excluded_topics]
          h[:custom_properties] = parsed_query.custom_properties_query_string
        end

        incl_repo_ids, excl_repo_ids = repo_filters(inputs)
        cap_repos!(hash, incl_repo_ids, excl_repo_ids)
      end

      def with_autofix!(hash)
        return if !CodeScanning::Autofix.any_enabled_for_org?(organization)

        valid_values = parsed_query.autofix_enum
        if !user.feature_enabled?(:autofix_alert_filter)
          # Filter away filters if the user is not allowed to see them
          valid_values = valid_values.select do |value|
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_GENERATED &&
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_ACCEPTED
          end
        end

        hash[:autofixes] = valid_values
      end

      def with_excluded_autofix!(hash)
        return if !CodeScanning::Autofix.any_enabled_for_org?(organization)

        valid_values = parsed_query.excluded_autofix_enum
        if !user.feature_enabled?(:autofix_alert_filter)
          # Filter away filters if the user is not allowed to see them
          valid_values = valid_values.select do |value|
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_GENERATED &&
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_ACCEPTED
          end
        end

        hash[:excluded_autofixes] = valid_values
      end

      def with_campaign!(hash)
        filter_campaign!(hash, include: @parsed_query.campaign_enum, exclude: @parsed_query.excluded_campaign_enum, organization_ids: [organization.id], user: user)
      end

      private

      def filter_mode(excluded_repo_ids)
        excluded_repo_ids.present? ? "exclusive" : "inclusive"
      end

      def cap_repos!(hash, incl_repo_ids, excl_repo_ids)
        # if both filters are present, get the net ids
        if incl_repo_ids.present? && excl_repo_ids.present?
          incl_repo_ids -= excl_repo_ids
          excl_repo_ids.clear
        end

        net_repo_ids =
          if excl_repo_ids.present?
            excl_repo_ids
          else
            incl_repo_ids
          end

        repo_ids_size = net_repo_ids&.size || -1

        if repo_ids_size > REPO_IDS_SIZE_LIMIT
          net_repo_ids.slice!(0...REPO_IDS_SIZE_LIMIT)
          filter_mode = filter_mode(excl_repo_ids)

          log_warn(
            "Repo ID limit surpassed: #{repo_ids_size}",
            "gh.security_products.feature_type": "code-scanning",
            "gh.org.id": organization.id,
            "gh.org.login": organization.display_login,
            "gh.security_products.search.query": parsed_query.raw_query,
          )
        end

        GitHub.dogstats.distribution(
          "security_center.alert_query_service.repo_ids_count.dist",
          repo_ids_size,
          tags: [
            "scope:org",
            "feature:code-scanning",
            "filter-mode:#{filter_mode}",
            "exceeds-limit:#{repo_ids_size > REPO_IDS_SIZE_LIMIT}",
          ],
        )

        if incl_repo_ids.present?
          hash[:excluded_repository_ids]&.clear
          hash[:repository_ids] = net_repo_ids
        end

        hash[:excluded_repository_ids] = net_repo_ids if excl_repo_ids.present?
      end

      def repo_filters(inputs)
        filters = ::SecurityCenter::FilterMappers::ToRepositoryIds.new(
          ::SecurityCenter::FilterMappers::ToRepositoryIds::InputFilters.new(**inputs),
          repo_ids_scope: allowed_repository_ids,
          orgs: [organization],
          user: user,
          user_session: user_session
        ).to_filters

        raise EmptyResultError if filters == ::SecurityCenter::FilterMappers::ToRepositoryIds::FALSE_FILTERS

        filters
      end
    end
  end
end

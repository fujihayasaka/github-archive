# typed: true
# frozen_string_literal: true

module CodeScanning
  class AlertQueryService
    class BusinessScopeStrategy < ScopeStrategy
      include GitHub::Memoizer

      sig { returns(User) }
      attr_reader :user

      sig { returns(UserSession) }
      attr_reader :user_session

      sig { returns(Business) }
      attr_reader :business

      sig { returns(T.any(T::Array[Organization], ActiveRecord::Relation)) }
      attr_reader :organizations

      sig { returns(Search::Queries::SecurityCenter::CodeScanningBusinessQuery) }
      attr_reader :parsed_query

      sig do
        params(
          user: User,
          user_session: UserSession,
          business: Business,
          organizations: T.any(T::Array[Organization], ActiveRecord::Relation),
          parsed_query: Search::Queries::SecurityCenter::CodeScanningBusinessQuery
        ).void
      end
      def initialize(user:, user_session:, business:, organizations:, parsed_query:)
        @user = user
        @user_session = user_session
        @business = business
        @organizations = organizations
        @parsed_query = parsed_query
      end

      memoize def selected_organizations
        # Examples
        #   org:a          — Return org a.
        #   -org:a         — Return everything but org a.
        #   org:a -org:a   — Return [].
        #   org:a -org:b   — Return org a.
        #   org:a -org:a,b — Return [].
        #   org:a,b -org:b — Return org a.

        selected = filter_authorized_orgs_by_names(parsed_query.organization_names)
        negated = filter_authorized_orgs_by_names(parsed_query.excluded_organization_names)

        if parsed_query.organization_names.present?
          selected - negated
        elsif parsed_query.excluded_organization_names.present?
          organizations - negated
        else
          organizations
        end
      end

      def scope
        :business
      end

      # @return [GitHub::SecurityCenter::TenantFilteringHelper::RequestScope]
      def tenant_filter_scope
        GitHub::SecurityCenter::TenantFilteringHelper::RequestScope.new(
          :business,
          business,
          SecurityCenter::SecurityFeatures::CODE_SCANNING
        )
      end

      def tenant_id
        @business.id
      end

      def tenant_name
        @business.slug
      end

      def with_owner_ids!(hash)
        hash[:owner_ids] = selected_organizations.map(&:id)
        raise EmptyResultError if hash[:owner_ids].empty?
      end

      def with_repository_ids!(hash, exclude_filter_type: nil)
        inputs = {}.tap do |h|
          h[:names] = [parsed_query.repository_names, parsed_query.excluded_repository_names] unless exclude_filter_type == :repo
          h[:teams] = [parsed_query.team_names, parsed_query.excluded_team_names]
          h[:topics] = [parsed_query.topics, parsed_query.excluded_topics]
        end

        incl_repo_ids, excl_repo_ids = repo_filters(inputs)

        # Signal that the query should return no results
        raise EmptyResultError if incl_repo_ids.present? && incl_repo_ids.first == 0

        cap_repos!(hash, incl_repo_ids, excl_repo_ids)
      end

      def with_autofix!(hash)
        return if !CodeScanning::Autofix.any_allowed_by_business?(business)

        valid_values = parsed_query.autofix_enum
        if !user.feature_flag_enabled?(:autofix_alert_filter, default: false)
          # Filter away filters if the user is not allowed to see them
          valid_values = valid_values.select do |value|
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_GENERATED &&
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_ACCEPTED
          end
        end

        hash[:autofixes] = valid_values
      end

      def with_excluded_autofix!(hash)
        return if !CodeScanning::Autofix.any_allowed_by_business?(business)

        valid_values = parsed_query.excluded_autofix_enum
        if !user.feature_flag_enabled?(:autofix_alert_filter, default: false)
          # Filter away filters if the user is not allowed to see them
          valid_values = valid_values.select do |value|
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_GENERATED &&
            value != Turboscan::Proto::AutofixFilter::AUTOFIX_FILTER_ACCEPTED
          end
        end

        hash[:excluded_autofixes] = valid_values
      end

      def with_campaign!(hash)
        filter_campaign!(hash, include: @parsed_query.campaign_enum, exclude: @parsed_query.excluded_campaign_enum, organization_ids: selected_organizations.map(&:id), user: user)
      end

      def with_assignees!(hash)
        filter_assignees!(hash, current_user: user)
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
            "gh.business.id": business.id,
            "gh.business.name": business.name,
            "gh.security_products.search.query": parsed_query.raw_query,
          )
        end

        GitHub.dogstats.distribution(
          "security_center.alert_query_service.repo_ids_count.dist",
          repo_ids_size,
          tags: [
            "scope:business",
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

      def filter_authorized_orgs_by_names(org_names)
        return [] if org_names.empty?

        org_names_set = org_names.map(&:downcase).to_set
        organizations.select { |org| org_names_set.include?(org.name.downcase) }
      end

      def repo_filters(inputs)
        filters = ::SecurityCenter::FilterMappers::ToRepositoryIds.new(
          ::SecurityCenter::FilterMappers::ToRepositoryIds::InputFilters.new(**inputs),
          repo_ids_scope: nil, # At the business level, only org owners/security managers can see data, so we don't need to scope by repos here.
          orgs: selected_organizations.to_a,
          user: user,
          user_session: user_session
        ).to_filters

        raise EmptyResultError if filters == ::SecurityCenter::FilterMappers::ToRepositoryIds::FALSE_FILTERS

        filters
      end
    end
  end
end

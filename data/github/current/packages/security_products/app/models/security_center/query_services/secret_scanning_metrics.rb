# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module QueryServices
    class SecretScanningMetrics
      extend T::Sig
      include GitHub::Memoizer

      QueryParser = ::Search::Queries::SecurityCenter::QueryParser
      MetricsService = ::SecretScanning::Services::MetricsService
      Filters = ::SecurityOverviewAnalytics::Filters
      AlertRevision = ::SecurityOverviewAnalytics::SecretScanningAlertRevision

      class NoDataResponse < T::Struct
        const :no_data, String, default: "No repositories found"
      end

      sig { returns(T.any(::Organization, ::Business)) }; attr_reader :scope
      sig { returns(User) }; attr_reader :user
      sig { returns(UserSession) }; attr_reader :user_session
      sig { returns(QueryParser) }; attr_reader :query_parser
      sig { returns(T.nilable(Date)) }; attr_reader :start_date
      sig { returns(T.nilable(Date)) }; attr_reader :end_date
      sig { returns(T.nilable(T::Array[Integer])) }; attr_reader :allowed_repo_ids
      sig { returns(T.nilable(T::Array[::Organization])) }; attr_reader :authorized_orgs

      sig do
        params(
          scope: T.any(::Organization, ::Business),
          user: User,
          user_session: UserSession,
          query_parser: QueryParser,
          start_date: T.nilable(Date),
          end_date: T.nilable(Date),
          allowed_repo_ids: T.nilable(T::Array[Integer]),
          authorized_orgs: T.nilable(T::Array[Organization]),
        ).void
      end
      def initialize(scope:, user:, user_session:, query_parser:, start_date: nil, end_date: nil, allowed_repo_ids: nil, authorized_orgs: nil)
        raise ArgumentError, "`authorized_orgs` required with business scope." if scope.is_a?(::Business) && authorized_orgs.nil?

        @scope = scope
        @user = user
        @user_session = user_session
        @query_parser = query_parser
        @start_date = start_date
        @end_date = end_date
        @allowed_repo_ids = allowed_repo_ids
        @authorized_orgs = authorized_orgs
      end

      sig do
        returns([
          T.any(NoDataResponse, SecretScanning::Models::PushProtectionMetrics),
          T::Boolean
        ])
      end
      def get_push_protection_metrics
        request_hash = T.let({}, T::Hash[Symbol, T.untyped])
        process_filters(request_hash)

        if request_hash[:no_data]
          return [NoDataResponse.new, false]
        end

        request_hash[:start_date] = start_date if start_date.present?
        request_hash[:end_date] = end_date if end_date.present?

        response, error = MetricsService.get_push_protection_metrics(scope, user, **request_hash)

        log_request(request_hash:, error:)

        if error.present? || response.nil?
          return [NoDataResponse.new, true]
        end

        [response, false]
      end

      sig do
        returns([
          T.any(NoDataResponse, T.nilable(SecretScanning::Models::PushProtectionMetricsForRepos)),
          T.any(T::Boolean, StandardError)
        ])
      end
      def get_push_protection_metrics_for_repos
        request_hash = T.let({}, T::Hash[Symbol, T.untyped])
        process_filters(request_hash)

        if request_hash[:no_data]
          return [NoDataResponse.new, false]
        end

        request_hash[:start_date] = start_date if start_date.present?
        request_hash[:end_date] = end_date if end_date.present?

        response, error = MetricsService.get_push_protection_metrics_for_repos(scope, user, **request_hash)

        log_request(request_hash:, error:)

        [response, error]
      end

      sig do
        params(cursor: T.nilable(String)).returns(
          T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]])
        )
      end
      def get_block_counts_by_token_type(cursor: nil)
        request_hash = T.let({}, T::Hash[Symbol, T.untyped])
        process_filters(request_hash)

        if request_hash[:no_data]
          return SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]].new(
            data: [],
            next_cursor: nil,
            previous_cursor: nil
          )
        end

        request_hash[:start_date] = start_date if start_date.present?
        request_hash[:end_date] = end_date if end_date.present?

        MetricsService.get_block_counts_by_token_type(scope, user, cursor, **request_hash)
      end

      sig do
        params(cursor: T.nilable(String)).returns(
          T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]])
        )
      end
      def get_block_counts_by_repo(cursor: nil)
        request_hash = T.let({}, T::Hash[Symbol, T.untyped])
        process_filters(request_hash)

        if request_hash[:no_data]
          return SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]].new(
            data: [],
            next_cursor: nil,
            previous_cursor: nil
          )
        end

        request_hash[:start_date] = start_date if start_date.present?
        request_hash[:end_date] = end_date if end_date.present?

        MetricsService.get_block_counts_by_repo(scope, user, cursor, **request_hash)
      end

      sig do
        params(cursor: T.nilable(String)).returns(
          T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]])
        )
      end
      def get_bypass_counts_by_token_type(cursor: nil)
        request_hash = T.let({}, T::Hash[Symbol, T.untyped])
        process_filters(request_hash)

        if request_hash[:no_data]
          return SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::TokenTypeCountMetric]].new(
            data: [],
            next_cursor: nil,
            previous_cursor: nil
          )
        end

        request_hash[:start_date] = start_date if start_date.present?
        request_hash[:end_date] = end_date if end_date.present?

        MetricsService.get_bypass_counts_by_token_type(scope, user, cursor, **request_hash)
      end

      sig do
        params(cursor: T.nilable(String)).returns(
          T.nilable(SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]])
        )
      end
      def get_bypass_counts_by_repo(cursor: nil)
        request_hash = T.let({}, T::Hash[Symbol, T.untyped])
        process_filters(request_hash)

        if request_hash[:no_data]
          return SecretScanning::Models::PaginatedResult[T::Array[SecretScanning::Models::RepoCountMetric]].new(
            data: [],
            next_cursor: nil,
            previous_cursor: nil
          )
        end

        request_hash[:start_date] = start_date if start_date.present?
        request_hash[:end_date] = end_date if end_date.present?

        MetricsService.get_bypass_counts_by_repo(scope, user, cursor, **request_hash)
      end

      private

      sig { returns(T::Boolean) }
      memoize def is_business_scope?
        scope.is_a?(::Business)
      end

      sig { returns(T::Boolean) }
      memoize def include_emus?
        return false unless is_business_scope?
        SecurityProduct::Permissions::BusinessAuthz.new(T.cast(scope, Business), actor: user).can_view_user_owned_repository_alerts?
      end

      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def process_filters(request_hash)
        if is_business_scope? && !include_emus? && T.must(authorized_orgs).empty?
          request_hash[:no_data] = true
          return
        end

        if !is_business_scope? && allowed_repo_ids&.empty?
          request_hash[:no_data] = true
          return
        end

        # Steps to process filters and fill request_hash.
        #
        # Since the same hash is updated by each step, please DO NOT
        # reorder the functions unless it is necessary and properly covered by
        # the tests.
        with_repository_owner_type_filters(request_hash)
        with_repository_owner_filters(request_hash)
        with_repository_attribute_filters(request_hash)
        with_secret_type_filter(request_hash)
        with_provider_filter(request_hash)
        with_validity_filter(request_hash)
      end

      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_repository_owner_type_filters(request_hash)
        return if request_hash[:no_data]
        return unless is_business_scope?

        request_input = T.let(
          request_hash[:repo_owners] ||= MetricsService::RepoOwnersFilters.new,
          MetricsService::RepoOwnersFilters
        )

        unless include_emus?
          request_input.owner_type = MetricsService::RepoOwnerType::Organization
          return
        end

        if T.must(authorized_orgs).empty?
          request_input.owner_type = MetricsService::RepoOwnerType::User
          allowed_types = %w(user)
        else
          allowed_types = %w(organization user)
        end

        filter_inputs = query_parser.get_positive_and_negative_qualified_values("owner-type")
        incl_owner_types = filter_inputs.first.map(&:downcase).uniq
        excl_owner_types = filter_inputs.last.map(&:downcase).uniq
        return if incl_owner_types.empty? && excl_owner_types.empty?

        if incl_owner_types.present?
          net_incl_types = allowed_types & (incl_owner_types - excl_owner_types)
        else
          net_incl_types = allowed_types - excl_owner_types
        end
        return if net_incl_types.size == allowed_types.size

        if net_incl_types.empty?
          request_hash[:no_data] = true
        elsif net_incl_types.first == "organization"
          request_input.owner_type = MetricsService::RepoOwnerType::Organization
        else
          request_input.owner_type = MetricsService::RepoOwnerType::User
        end
      end

      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_repository_owner_filters(request_hash)
        return if request_hash[:no_data]
        return unless is_business_scope?

        request_input = T.let(
          request_hash[:repo_owners] ||= MetricsService::RepoOwnersFilters.new,
          MetricsService::RepoOwnersFilters
        )

        filter_inputs = query_parser.get_positive_and_negative_qualified_values("owner")
        incl_owners = filter_inputs.first.map(&:downcase).uniq
        excl_owners = filter_inputs.last.map(&:downcase).uniq
        if incl_owners.empty? && excl_owners.empty?
          unless request_input.owner_type == MetricsService::RepoOwnerType::User
            request_input.org_ids = T.must(authorized_orgs).map { |org| T.must(org.id) }
          end
          return
        end

        if incl_owners.present?
          net_incl_owners = incl_owners - excl_owners
          if net_incl_owners.empty?
            request_hash[:no_data] = true
          else
            org_ids, user_ids = get_owner_ids(request_input.owner_type, net_incl_owners)
            if org_ids.blank? && user_ids.blank?
              request_hash[:no_data] = true
            else
              request_input.org_ids = org_ids
              request_input.user_ids = user_ids
              # "*_ids" inputs of metrics API apply to data of specific owner type and does not decide the overall scope of the result set.
              # And when RepoOwnerType::Any is set, API is expected to return data from both org and user owners no matter if any "*_ids" filter presents.
              # Here we need to force the owner type scope when user input results in one of them.
              if request_input.owner_type == MetricsService::RepoOwnerType::Any
                request_input.owner_type = MetricsService::RepoOwnerType::User if org_ids.blank? && user_ids.present?
                request_input.owner_type = MetricsService::RepoOwnerType::Organization if org_ids.present? && user_ids.blank?
              end
            end
          end
        else
          net_excl_owners = excl_owners - incl_owners
          return if net_excl_owners.empty?

          org_ids, user_ids = get_owner_ids(request_input.owner_type, net_excl_owners)
          request_input.exclude_org_ids = org_ids
          request_input.exclude_user_ids = user_ids
        end
      end

      # TODO: logic of this function is to parse query input into request filters supported by metrics APIs
      # The current design is an initial approach to the problem and will be clean up and organized with future
      # PRs when we add support for visibility or owner filters.
      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_repository_attribute_filters(request_hash)
        return if request_hash[:no_data]

        archived_filter_applied = T.let(false, T::Boolean)
        any_non_archived_filter_applied = T.let(false, T::Boolean)
        filters = repository_attribute_filters(query_parser)

        filters.each do |filter|
          if filter.is_a?(::SecurityOverviewAnalytics::Filters::ByArchived)
            archived_filter_applied ||= !filter.is_empty?
          else
            any_non_archived_filter_applied ||= !filter.is_empty?
          end
          break if archived_filter_applied && any_non_archived_filter_applied
        end

        unless any_non_archived_filter_applied || archived_filter_applied
          request_hash[:repo_ids] = allowed_repo_ids if allowed_repo_ids.present?
          return
        end

        # Metrics APIs support direct filtering with repo archived state.
        # Process archived filter inputs directly when it is the only filter presents.
        unless any_non_archived_filter_applied
          filters = query_parser.get_positive_and_negative_qualified_values("archived")
          incl_archived_states = T.let(filters.first.uniq.map(&:to_sym), T::Array[Symbol])
          excl_archived_states = T.let(filters.last.uniq.map(&:to_sym), T::Array[Symbol])
          return if incl_archived_states.empty? && excl_archived_states.empty?

          allowed_states = [:true, :false]
          if incl_archived_states.present?
            net_incl_states = allowed_states & (incl_archived_states - excl_archived_states)
          else
            net_incl_states = allowed_states - excl_archived_states
          end

          # All repo archived stats are in-scope, do nothing since that's the default for metrics API.
          return if net_incl_states.size == 2

          if net_incl_states.empty?
            request_hash[:no_data] = true
          else
            request_hash[:repos_in_archived_state] = net_incl_states.first == :true
            # Even though TSS can directly handle the archived filter, we still need to
            # limit the repos by what the user is authz to see.
            request_hash[:repo_ids] = allowed_repo_ids if allowed_repo_ids.present?
          end
          return
        end

        has_any_incl_filter = filters.any? { |filter| filter.has_incl_filters? }

        # When positive filter exists, filtered repository ids are bounded.
        # Perform query normally and update request hash
        if has_any_incl_filter
          repo_ids = get_repository_ids(filters)
          if repo_ids.present?
            request_hash[:repo_ids] = repo_ids
          else
            request_hash[:no_data] = true
          end
          return
        end

        # When only negated filters exist, only need to update `exclude_repo_ids` input of request hash.
        # Perform query on negated filter values as if they are positive filters.
        query_parser_with_reversed_negated_filters = query_parser.reverse_negated_prefix
        reversed_filters = repository_attribute_filters(query_parser_with_reversed_negated_filters)
        repo_ids = get_repository_ids(reversed_filters)

        if allowed_repo_ids.nil?
          request_hash[:exclude_repo_ids] = repo_ids
          return
        end

        # Optimizations when allowed_repo_ids exists (non admins)
        reduced_repo_ids_scope = T.must(allowed_repo_ids) - repo_ids
        if reduced_repo_ids_scope.empty?
          request_hash[:no_data] = true
        else
          request_hash[:repo_ids] = reduced_repo_ids_scope
        end
      end

      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_secret_type_filter(request_hash)
        return if request_hash[:no_data]

        filter = Filters::SecretScanning::ByTokenTypeSlug.new(*query_parser.get_positive_and_negative_qualified_values(
          AlertRevision::QUALIFIER_SECRET_TYPE,
          qualifier_alias: AlertRevision::QUALIFIER_SECRET_TYPE_ALIAS
        ))
        return if filter.is_empty?

        request_input = T.let(
          request_hash[:token_filters] ||= MetricsService::PushProtectionTokenFilters.new,
          MetricsService::PushProtectionTokenFilters
        )
        request_input.token_types = filter.incl_filters
        request_input.exclude_token_types = filter.excl_filters
      end

      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_provider_filter(request_hash)
        return if request_hash[:no_data]

        filter = Filters::SecretScanning::ByTokenProvider.new(*query_parser.get_positive_and_negative_qualified_values(
          AlertRevision::QUALIFIER_PROVIDER,
          qualifier_alias: AlertRevision::QUALIFIER_PROVIDER_ALIAS
        ))
        return if filter.is_empty?

        request_input = T.let(
          request_hash[:token_filters] ||= MetricsService::PushProtectionTokenFilters.new,
          MetricsService::PushProtectionTokenFilters
        )
        request_input.token_providers = filter.incl_filters
        request_input.exclude_token_providers = filter.excl_filters
      end

      sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
      def with_validity_filter(request_hash)
        return if request_hash[:no_data]

        filter = Filters::SecretScanning::ByValidity.new(*query_parser.get_positive_and_negative_qualified_values(
          AlertRevision::QUALIFIER_VALIDITY,
          qualifier_alias: AlertRevision::QUALIFIER_VALIDITY_ALIAS
        ))
        return if filter.is_empty?

        request_input = T.let(
          request_hash[:token_filters] ||= MetricsService::PushProtectionTokenFilters.new,
          MetricsService::PushProtectionTokenFilters
        )
        request_input.token_validities = filter.to_token_validities(filter.incl_filters)
        request_input.exclude_token_validities = filter.to_token_validities(filter.excl_filters)
      end

      sig { params(owner_type: MetricsService::RepoOwnerType, logins: T::Array[String]).returns([T.nilable(T::Array[Integer]), T.nilable(T::Array[Integer])]) }
      def get_owner_ids(owner_type, logins)
        return [nil, nil] unless is_business_scope?

        org_ids = if owner_type != MetricsService::RepoOwnerType::User
          T.must(authorized_orgs).filter_map { |org| org.id if logins.include?(org.display_login.downcase) }
        end

        user_ids = if include_emus? || owner_type != MetricsService::RepoOwnerType::Organization
          ::SecurityCenter::Helpers::EnterpriseManagedUsers.new(business: T.cast(scope, ::Business)).find_ids(logins: logins)
        end

        [org_ids, user_ids]
      end

      sig { params(filters: T::Array[T.any(Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)]).returns(T::Array[Integer]) }
      def get_repository_ids(filters)
        organizations = is_business_scope? ? T.must(authorized_orgs) : [T.cast(scope, ::Organization)]

        ::SecurityOverviewAnalytics::Repository
          .then do |rel|
            next rel.where(business_id: scope.id) if is_business_scope?
            rel
          end
          .then do |rel|
            org_owner_rel = rel.where(owner_id: organizations.map(&:id), owner_type: "Organization")
            if is_business_scope? && include_emus?
              org_owner_rel.or(rel.where(owner_type: "User"))
            else
              org_owner_rel
            end
          end
          .then do |rel|
            next rel if allowed_repo_ids.nil?
            rel.where(repository_id: allowed_repo_ids)
          end
          .then do |rel|
            filters.reduce(rel) { |r, filter| filter.apply(r) }
          end
          .pluck(:repository_id)
      end

      sig { params(query_parser: QueryParser).returns(T::Array[T.any(Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)]) }
      def repository_attribute_filters(query_parser)
        organizations = is_business_scope? ? T.must(authorized_orgs) : [T.cast(scope, ::Organization)]

        filters = T.let([
          Filters::ByArchived.new(*query_parser.get_positive_and_negative_qualified_values("archived")),
          Filters::ByRepository.new(query_parser.get_unqualified_values, [], substring_match: true, scope:),
          Filters::ByRepository.new(*query_parser.get_positive_and_negative_qualified_values("repo"), substring_match: false, scope:),
          Filters::ByTeam.new(*query_parser.get_positive_and_negative_qualified_values("team"), organizations:, user:),
          Filters::ByTopic.new(*query_parser.get_positive_and_negative_qualified_values("topic"), organizations:),
          Filters::ByVisibility.new(*query_parser.get_positive_and_negative_qualified_values("visibility")),
        ], T::Array[T.any(Filters::Filter, ::SecurityCenter::Filters::ByCustomProperty)])

        unless is_business_scope?
          filters << ::SecurityCenter::Filters::ByCustomProperty.new(
            allowed_repo_ids:,
            query: query_parser.custom_properties_string,
            org: T.cast(scope, ::Organization),
            user:,
            user_session:
          )
        end

        filters
      end

      sig do
        params(
          request_hash: T::Hash[Symbol, T.untyped],
          error: T.any(T::Boolean, StandardError, Twirp::Error),
        ).void
      end
      def log_request(request_hash:, error:)
        scope_info = if scope.is_a?(::Business)
          {
            "gh.business.id": scope.id,
            "gh.business.name": scope.name,
          }
        else
          {
            "gh.org.id": scope.id,
            "gh.org.login": scope.display_login,
          }
        end

        log_hash = {
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_center.start_date": start_date,
          "gh.security_center.end_date": end_date,
          "gh.security_center.repo_ids.size": request_hash[:repo_ids]&.size || 0,
          "gh.security_center.exclude_repo_ids.size": request_hash[:exclude_repo_ids]&.size || 0,
          "gh.security_center.repos_in_archived_state": request_hash[:repos_in_archived_state],
          "gh.user.id": user.id,
          "gh.user.login": user.display_login,
          **scope_info,
        }

        if error == false
          GitHub.logger.info("Secret scanning metrics API request suceeded.", log_hash)
          return
        end

        if error.is_a?(StandardError) || error.is_a?(Twirp::Error)
          Failbot.report(error, log_hash)

          log_hash["exception.type"] = error.class.name
          log_hash["exception.message"] = if error.is_a?(StandardError)
            error.message
          elsif error.is_a?(Twirp::Error)
            error.msg
          end
        end
        GitHub.logger.error("Secret scanning metrics API request failed.", log_hash)
      end
    end
  end
end

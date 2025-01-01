# typed: true
# frozen_string_literal: true

module SecretScanning
  ##
  # Domain service for fetching token alerts and filters from token-scanning backend.
  class AlertQueryService
    include ::SecurityCampaigns::AlertQueryServiceInterface
    include SecretScanning::Encryption::EncryptedSecretsHelper
    include GitHub::TokenScanning::SecretScanningHelper
    include GitHub::SecurityCenter::TenantFilteringHelper
    include SecretScanning::Features::FeatureFlagHelper

    ##
    # Indicates an "invalid" query - that is, one that would return no results.
    class InvalidQueryError < StandardError; end

    ##
    # Create an instance of AlertQueryService for business-level experiences
    sig do
      params(
        business: Business,
        organizations: T.any(T::Array[Organization], ActiveRecord::Relation),
        current_user: User,
        user_session: UserSession,
        query: T.nilable(String),
      ).returns(SecretScanning::AlertQueryService)
    end
    def self.for_business(business:, organizations:, current_user:, user_session:, query: nil)
      generic_results_available = SecretScanning::Features::Business::GenericSecrets.new(business).feature_available? ||
        SecretScanning::Features::Business::LowerConfidencePatterns.new(business).feature_available?
      parsed_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: query, allow_results_category: generic_results_available)
      strategy = BusinessScopeStrategy.new(user: current_user, user_session: user_session, business: business, organizations: organizations, parsed_query: parsed_query)
      new(strategy: strategy, parsed_query: parsed_query, current_user: current_user)
    end

    ##
    # Create an instance of AlertQueryService for organization-level experiences
    sig do
      params(
        organization: Organization,
        current_user: User,
        user_session: T.nilable(UserSession),
        allowed_repository_ids: T.nilable(T::Array[Integer]),
        query: T.nilable(String),
        security_campaign_ids: T.nilable(T::Array[Integer]),
      ).returns(SecretScanning::AlertQueryService)
    end
    def self.for_organization(organization:, current_user:, user_session:, allowed_repository_ids: nil, query: nil, security_campaign_ids: nil)
      low_conf_secrets_available = SecretScanning::Features::Org::GenericSecrets.new(organization).feature_available? ||
        SecretScanning::Features::Org::LowerConfidencePatterns.new(organization).feature_available?
      parsed_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: query, allow_results_category: low_conf_secrets_available)
      strategy = OrganizationScopeStrategy.new(user: current_user, user_session: user_session, organization: organization, allowed_repository_ids: allowed_repository_ids, parsed_query: parsed_query)
      new(strategy: strategy, parsed_query: parsed_query, current_user: current_user, security_campaign_ids: security_campaign_ids)
    end

    ##
    # Create an instance of AlertQueryService for repository-level experiences
    sig do
      params(
        repository: Repository,
        current_user: User,
        query: T.nilable(String),
      ).returns(SecretScanning::AlertQueryService)
    end
    def self.for_repository(repository:, current_user:, query: nil)
      low_conf_secrets_available = SecretScanning::Features::Repo::GenericSecrets.new(repository).feature_available? ||
        SecretScanning::Features::Repo::LowerConfidencePatterns.new(repository).feature_available?
      parsed_query = Search::Queries::SecurityCenter::SecretScanningQuery.new(query: query, allow_results_category: low_conf_secrets_available)
      strategy = RepositoryScopeStrategy.new(repository: repository, parsed_query: parsed_query)
      new(strategy: strategy, parsed_query: parsed_query, current_user: current_user)
    end

    # disable external callers from using initializer
    # instances must be created via provided scope-specific factory methods
    private_class_method :new

    sig { returns(ScopeStrategy) }
    attr_reader :strategy

    sig { returns(User) }
    attr_reader :current_user

    sig { returns(Search::Queries::SecurityCenter::SecretScanningQuery) }
    attr_reader :parsed_query

    sig { returns(T.nilable(T::Array[Integer])) }
    attr_reader :security_campaign_ids

    ##
    # (private) Create an instance.
    sig do
      params(
        strategy: ScopeStrategy,
        parsed_query: Search::Queries::SecurityCenter::SecretScanningQuery,
        current_user: User,
        security_campaign_ids: T.nilable(T::Array[Integer]),
      ).void
    end
    def initialize(strategy:, parsed_query:, current_user:, security_campaign_ids: nil)
      @strategy = strategy
      @parsed_query = T.let(parsed_query, Search::Queries::SecurityCenter::SecretScanningQuery)
      @current_user = current_user
      @security_campaign_ids = security_campaign_ids
    end

    ##
    # Fetch a page of alerts.
    #
    # @param page [Number] the current page index, 1-based
    # @param per_page [Number] the number of items to return per-page
    # @return Array<(Array<Token>, Number, Number, Object, Boolean)>
    #   Array<Token>  alerts
    #   Number        number of open alerts
    #   Number        number of closed alerts
    #   Object        raw service response
    #   String        error message if a backend error was encountered
    sig { params(page: Integer, per_page: Integer).returns([T::Array[GitHub::TokenScanning::Service::Token], Integer, Integer, T.untyped, T.nilable(String)]) }
    def get_alerts(page: 1, per_page: 25)
      # Delegate to the cursor-aware variant without providing cursors
      alerts, open_count, closed_count, response, err = get_alerts_with_response(page: page, per_page: per_page)
      [alerts, open_count, closed_count, response, err]
    end

    ##
    # Same as get_alerts but supports cursor-based paging while remaining backward-compatible.
    # If before_cursor/after_cursor is provided, offset paging (page) is ignored and page is set to 0.
    #
    # @param before_cursor [String, nil] the cursor to fetch the previous page
    # @param after_cursor [String, nil] the cursor to fetch the next page
    # @param page [Number, nil] the current page index, 1-based (ignored when cursors provided)
    # @param per_page [Number] the number of items to return per-page
    # @return Array<(Array<Token>, Number, Number, Object, Boolean)>
    #   Array<Token>  alerts
    #   Number        number of open alerts
    #   Number        number of closed alerts
    #   Object        raw service response
    #   String        error message if a backend error was encountered
    sig { params(before_cursor: T.nilable(String), after_cursor: T.nilable(String), page: T.nilable(Integer), per_page: Integer).returns([T::Array[GitHub::TokenScanning::Service::Token], Integer, Integer, T.untyped, T.nilable(String)]) }
    def get_alerts_with_response(before_cursor: nil, after_cursor: nil, page: nil, per_page: 25)
      empty_response = [[], 0, 0, nil, nil]

      return empty_response unless parsed_query.is_valid?

      # build request object from user filter
      request_hash = {}
      begin
        with_selector!(request_hash)
        with_feature_flags!(request_hash)
        with_token_state!(request_hash)
        with_token_types!(request_hash)
        with_token_providers!(request_hash)
        with_resolution!(request_hash)
        with_validity!(request_hash)
        with_campaign_states!(request_hash)
        with_bypassed!(request_hash)
        with_results_category!(request_hash)
        with_security_campaign_ids!(request_hash)
        with_sort!(request_hash)
        with_assignees!(request_hash)

        # Apply paging. If cursors are present, force page to 0 (cursor mode)
        cursor_provided = !before_cursor.nil? || !after_cursor.nil?
        with_paging!(request_hash, cursor_provided ? 0 : (page || 1), per_page)
        with_cursor_paging!(request_hash, before_cursor, after_cursor)

        with_publicly_leaked!(request_hash)
        with_multi_repo!(request_hash)
      rescue InvalidQueryError
        return empty_response
      end

      # invoke service
      request = GitHub::Proto::SecretScanning::Api::V2::GetTokensRequest.new(request_hash)
      response = GitHub::TokenScanning::Service::Client.new(current_user).get_tokens(request.to_h)
      response_data = response.try(:data)

      # if there was a service error, return an array with the request_error set to true
      if response.nil? || response_data.nil? || response.error.present?
        err_msg = response&.error&.msg || "Failed to load alerts"
        Failbot.report(SecretScanning::Errors::ServiceError.new(err_msg), app: SecretScanning::Constants::FAILBOT_APP_NAME)
        return [[], 0, 0, nil, err_msg]
      end

      [
        map_tokens_to_alerts(
          *filter_tenant_rows(
            strategy.tenant_filter_scope,
            response_data.try(:tokens) || [],
            -> (t) { t.repository_id }
          )
        ),
        response_data.try(:unresolved_count) || 0,
        response_data.try(:resolved_count) || 0,
        response,
        nil
      ]
    end

    ##
    # Fetch repository counts for alert groups.
    #
    # @return Array<(Array<RepoCount>, Boolean, ServiceResponse)>
    #   Array<RepoCount>   repository counts from API with structured protobuf objects
    #   Boolean            true if there was a backend error, or false for success
    #   ServiceResponse    raw service response
    sig do
      override.returns([
        T::Array[GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount],
        T::Boolean,
        T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse)
      ])
    end
    def counts_by_repo
      empty_response = [[], false, nil]
      error_response = [[], true, nil]

      return empty_response unless parsed_query.is_valid?

      # build request object from user filter - use REPOSITORY aggregation to get repo counts
      request_hash = {
        aggregations: [GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByAggregation::REPOSITORY]
      }
      begin
        with_selector!(request_hash)
        with_feature_flags!(request_hash)
        with_token_state!(request_hash)
        with_token_types!(request_hash)
        with_token_providers!(request_hash)
        with_resolution!(request_hash)
        with_validity!(request_hash)
        with_campaign_states!(request_hash)
        with_security_campaign_ids!(request_hash)
        with_bypassed!(request_hash)
        with_results_category!(request_hash)
        with_assignees!(request_hash)
        with_publicly_leaked!(request_hash)
        with_multi_repo!(request_hash)
      rescue InvalidQueryError
        return empty_response
      end

      # invoke service
      request = GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsRequest.new(request_hash)
      response = GitHub::TokenScanning::Service::Client.new(current_user).get_token_group_by_counts(request.to_h)
      response_data = T.let(response.try(:data), T.nilable(GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse))

      # if there was a service error, return an array with the request_error set to true
      return error_response if response.nil? || response_data.nil? || response.error.present?

      # Extract repository counts from the response
      repo_counts = T.let(
        [],
        T::Array[GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsResponse::AggregationCount::RepoTokenCountAggregation::RepoCount]
      )

      (response_data.try(:counts) || []).each do |agg|
        repo_aggregation = agg.try(:repo_aggregation)
        if repo_aggregation&.present?
          # Convert protobuf RepeatedField to Array to match return type signature
          repo_counts = (repo_aggregation.try(:counts) || []).to_a
          break
        end
      end

      [repo_counts, false, response_data]
    end

    ##
    # Fetch the options for a given filter type.
    #
    # @param filter [String] one of the filter types defined by `GroupByAggregation`
    # @returns Array<(Array<Object>, Boolean)>
    #   Array<Array<Object>>  array of option groups, each with an array of items and optional title
    #   Boolean               true if there was a backend error, or false for success
    def get_filter_options(filter:)
      empty_response = [[], false]
      error_response = [[], true]

      return error_response unless SecretScanningControllerHelper::GroupByAggregation::TO_SERVICE_ENUM[filter].present?
      return empty_response unless parsed_query.is_valid?

      # build request object from user filter
      request_hash = {
        aggregations: [T.must(SecretScanningControllerHelper::GroupByAggregation::TO_SERVICE_ENUM[filter])]
      }
      begin
        with_selector!(request_hash, aggregation_filter: filter)
        with_feature_flags!(request_hash)
        with_token_state!(request_hash)
        with_results_category!(request_hash)
        with_token_types!(request_hash) unless filter == SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE
        with_token_providers!(request_hash) unless filter == SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER
        with_assignees!(request_hash)
      rescue InvalidQueryError
        return empty_response
      end

      # invoke service
      request = GitHub::Proto::SecretScanning::Api::V2::GetTokenGroupByCountsRequest.new(request_hash)
      response = GitHub::TokenScanning::Service::Client.new(current_user).get_token_group_by_counts(request.to_h)
      response_data = response.try(:data)

      # if there was a service error, return an array with the request_error set to true
      return error_response if response.nil? || response_data.nil? || response.error.present?

      (response_data.try(:counts) || []).each do |agg|
        if filter == SecretScanningControllerHelper::GroupByAggregation::TOKEN_TYPE && agg.type_aggregation.present?
          return map_secret_type_aggregation_counts(agg.type_aggregation)
        end

        if filter == SecretScanningControllerHelper::GroupByAggregation::TOKEN_PROVIDER && agg.provider_aggregation.present?
          return map_secret_provider_aggregation_counts(agg.provider_aggregation)
        end

        if filter == SecretScanningControllerHelper::GroupByAggregation::REPOSITORY && agg.repo_aggregation.present?
          return strategy.map_filter_options(filter, agg.repo_aggregation)
        end

        if filter == SecretScanningControllerHelper::GroupByAggregation::OWNER && agg.repo_aggregation.present?
          return strategy.map_filter_options(filter, agg.repo_aggregation)
        end
      end

      # return an empty set if TSS returns no data
      # this is not an error condition for dotcom
      empty_response
    end

    sig { returns(T.nilable(Integer)) }
    def generic_results_alert_count
      return nil unless parsed_query.is_valid?

      request_hash = {
        low_confidence: true
      }
      begin
        with_selector!(request_hash)
        with_feature_flags!(request_hash)
        with_assignees!(request_hash)
      rescue InvalidQueryError
        return nil
      end
      GitHub::TokenScanning::Service::Client.new(@current_user).get_token_counts(request_hash)&.data&.unresolved_count
    end

    ##
    # Fetch alert counts.
    #
    # @param include_resolved [Boolean] whether to include resolved alerts in the count (default: false)
    # @return Array<(Integer, Integer, String)>
    #   Integer       number of open alerts
    #   Integer       number of closed alerts
    #   String        error message if a backend error was encountered, nil otherwise
    sig { params(include_resolved: T::Boolean).returns([Integer, Integer, T.nilable(String)]) }
    def get_alert_counts(include_resolved: false)
      empty_response = [0, 0, nil]

      return empty_response unless parsed_query.is_valid?

      request_hash = {}
      begin
        with_selector!(request_hash)
        with_feature_flags!(request_hash)
        with_security_campaign_ids!(request_hash)
      rescue InvalidQueryError
        return empty_response
      end

      request_hash[:include_resolved] = include_resolved

      response = GitHub::TokenScanning::Service::Client.new(current_user).get_token_counts(request_hash)

      errored, err = SecretScanning::Services::ServiceHelper.process_response(
        response: response,
        operation: "getting alert counts",
        is_404_ok: false,
        failbot_attributes: { "user.id": current_user.id }
      )

      if errored
        err_msg = err&.message || "Failed to load alert counts"
        return [0, 0, err_msg]
      end

      response_data = response.data
      unresolved_count = response_data.try(:unresolved_count) || 0
      resolved_count = response_data.try(:resolved_count) || 0

      [unresolved_count, resolved_count, nil]
    end

    def self.filter_count_by_state(open_count, closed_count, parsed_query)
      return open_count + closed_count if parsed_query.is_no_state_page?
      return open_count if parsed_query.is_open_page?
      return closed_count if parsed_query.is_closed_page?
      open_count + closed_count
    end

    private

    def filter_count_by_state(open_count, closed_count)
      self.class.filter_count_by_state(open_count, closed_count, parsed_query)
    end

    def map_tokens_to_alerts(tokens_from_api, repos_by_id)
      token_id_to_internal_token_representations = {}

      repos_to_internal_token_representations = tokens_from_api.reduce({}) do |acc, token_from_api|
        repo = repos_by_id[token_from_api.repository_id]
        internal_token_representation = GitHub::TokenScanning::Service::Token.new(token_from_api, repo)

        # These are only being set to nil for now because we have yet to fetch the
        # the raw secrets for each token. We are setting it here to retain the original
        # ordering of tokens_from_api since ruby hashs retain the order in which key-value
        # pairs are created. See: https://ruby-doc.org/core-3.0.2/Hash.html#class-Hash-label-Entry+Order
        token_id_to_internal_token_representations[token_from_api.id] = nil

        acc[repo] ||= []
        acc[repo] << internal_token_representation
        acc
      end

      repos_to_internal_token_representations.each do |_repo, tokens|
        set_raw_secrets_from_encrypted_secrets(tokens)
        tokens_with_secrets, tokens_without_secrets = tokens.partition { |t| t.raw_secret.present? }

        tokens_with_secrets.each do |token|
          token_id_to_internal_token_representations[token.id] = token
        end

        tokens_without_secrets.each do |token|
          SecretScanning::Util::RawSecret.replacement_for_nil_raw_secret(token)
          token_id_to_internal_token_representations[token.id] = token
        end
      end

      # And extract the internal representation of the tokens from the hash
      ret = token_id_to_internal_token_representations.values.compact
      ret
    end

    def populate_token_contents(internal_token_representation, location_path, blob = nil)
      if location_path.nil?
        internal_token_representation.raw_secret = SecretScanning::Util::RawSecret::NO_PREVIEW_MESSAGE
        return
      end

      if blob.present?
        tree_entry = TreeEntry.new(
          internal_token_representation.repository,
          blob.merge("path" => location_path)
        )

        unless tree_entry.text?
          internal_token_representation.raw_secret = SecretScanning::Util::RawSecret::NO_PREVIEW_MESSAGE
          return
        end
      end

      internal_token_representation.raw_secret = SecretScanning::Util::RawSecret.get_raw_secret_from_first_location(
        internal_token_representation,
        internal_token_representation.repository,
        blob.nil? ? {} : { blob["oid"] => blob }
      )
    end

    ##
    # Map the `SecretTypeTokenCountAggregation` to a format that can be used by the frontend.
    def map_secret_type_aggregation_counts(type_aggregation)
      items = type_aggregation.counts.reduce([]) do |types, obj|
        add_new_item = T.let(true, T::Boolean)
        # If more than one type aggregation has the same slug, merge their counts to display one single entry in the filter.
        types.each do |item|
          if item[:slug] == obj.type.slug_value
            item[:count] += filter_count_by_state(obj.unresolved_count, obj.resolved_count)
            add_new_item = false
            break
          end
        end

        if add_new_item
          types << {
            count: filter_count_by_state(obj.unresolved_count, obj.resolved_count),
            label: obj.type.label_value,
            slug: obj.type.slug_value,
            type_value: obj.type.type_value # This will be the first token type matching the slug, but that's okay since the filter will still match all token types.
          }
        end

        types
      end

      items = SecurityCenterHelper.sort_items_with_counts(items)

      aggregates = T.let([
        {
          items: items.select { |item| !item[:type_value].start_with?("cp_") },
          title: "Service providers"
        }
      ], T::Array[{ items: T.untyped, title: String }])

      if strategy.show_custom_patterns?
        aggregates << {
            items: items.select { |item| item[:type_value].start_with?("cp_") },
            title: "Custom patterns"
          }
      end

      [aggregates, false]
    end

    ##
    # Map the `ProviderTokenCountAggregation` to a format that can be used by the frontend.
    def map_secret_provider_aggregation_counts(provider_aggregation)
      items = provider_aggregation.counts.map do |obj|
        {
          count: filter_count_by_state(obj.unresolved_count, obj.resolved_count),
          label: obj.provider_name,
          description: obj.provider_name,
          slug: obj.provider_name.downcase.gsub(" ", "_")
        }
      end

      [[{ items: SecurityCenterHelper.sort_items_with_counts(items) }], false]
    end

    def with_selector!(request_hash, aggregation_filter: nil)
      strategy.with_selector!(request_hash, aggregation_filter: aggregation_filter)
    end

    def with_feature_flags!(request_hash)
      request_hash[:feature_flags] = []
      strategy.with_feature_flags!(request_hash)
    end

    def with_token_state!(request_hash)
      request_hash[:token_state] = if parsed_query.is_no_state_page?
        GitHub::Proto::SecretScanning::Api::V2::TokenState::NO_STATE
      else
        parsed_query.alert_state_enums.first
      end
    end

    def with_token_types!(request_hash)
      return unless parsed_query.secret_types.present? || parsed_query.negated_secret_types.present?

      # Check net values for secret-type filter. Return early if there are conflicting values.
      included, excluded = net_qualifier_values(parsed_query.secret_types, parsed_query.negated_secret_types).values_at(:included, :excluded)
      raise InvalidQueryError if included.blank? && excluded.blank?

      request_hash[:token_slugs] = included
      request_hash[:exclude_token_slugs] = excluded
    end

    def with_token_providers!(request_hash)
      return unless parsed_query.secret_providers.present? || parsed_query.negated_secret_providers.present?

      # Check net values for provider filter. Return early if there are conflicting values.
      included, excluded = net_qualifier_values(parsed_query.secret_providers, parsed_query.negated_secret_providers).values_at(:included, :excluded)
      raise InvalidQueryError if included.blank? && excluded.blank?

      request_hash[:token_providers] = included
      request_hash[:exclude_token_providers] = excluded
    end

    def with_resolution!(request_hash)
      return unless parsed_query.resolutions_enums.present? || parsed_query.negated_resolutions_enums.present?

      # Check net values for resolution filter. Return early if there are conflicting values.
      included, excluded = net_qualifier_values(parsed_query.resolutions_enums, parsed_query.negated_resolutions_enums).values_at(:included, :excluded)
      raise InvalidQueryError if included.blank? && excluded.blank?

      request_hash[:resolution] = included
      request_hash[:exclude_resolutions] = excluded
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_validity!(request_hash)
      return unless parsed_query.validities_enums.present? || parsed_query.negated_validities_enums.present?

      # Check net values for resolution filter. Return early if there are conflicting values.
      included, excluded = net_qualifier_values(parsed_query.validities_enums, parsed_query.negated_validities_enums).values_at(:included, :excluded)
      raise InvalidQueryError if included.blank? && excluded.blank?

      # since `revoked` is consolidated into `inactive`, add `revoked`` when the user has requested `inactive``
      if included.include?(GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_INACTIVE)
        included << GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_REVOKED
      end
      # since `unverifiable` is consolidated into `unknown`, add `unverifiable`` when the user has requested `unknown``
      if included.include?(GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNKNOWN)
        included << GitHub::Proto::SecretScanning::Api::V2::TokenValidity::TOKEN_VALIDITY_UNVERIFIABLE
      end

      GitHub.logger.info(
        "filter by validity requested on secret scanning index page",
        "service.name": self.class.name,
        "strategy.name": strategy.class.name,
        "user.id": current_user.id,
        "query": parsed_query.query.to_s,
        "validity.included": included,
      )

      request_hash[:validity] = included

      # TODO: uncomment this once the backend supports excluding validities
      # request_hash[:exclude_validities] = excluded
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_bypassed!(request_hash)
      return unless parsed_query.bypassed_enums.present? || parsed_query.negated_bypassed_enums.present?

      # Check net values for resolution filter. Return early if there are conflicting values.
      included, excluded = net_qualifier_values(parsed_query.bypassed_enums, parsed_query.negated_bypassed_enums).values_at(:included, :excluded)
      raise InvalidQueryError if included.blank? && excluded.blank?

      GitHub.logger.info(
        "filter by bypass state requested on secret scanning index page",
        "service.name": self.class.name,
        "strategy.name": strategy.class.name,
        "user.id": current_user.id,
        "query": parsed_query.query.to_s,
        "bypass.included": included,
      )

      request_hash[:bypassed] = included.include?(Search::Queries::SecurityCenter::SecretScanningQuery::BYPASSED_TRUE_ENUM)
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_publicly_leaked!(request_hash)
      included = parsed_query.publicly_leaked_enums
      return unless included.present?

      GitHub.logger.info(
        "filter for publicly leaked requested on secret scanning index page",
        "service.name": self.class.name,
        "strategy.name": strategy.class.name,
        "user.id": current_user.id,
        "query": parsed_query.query.to_s,
        "publicly_leaked.included": included,
      )

      request_hash[:publicly_leaked] = included.include?(Search::Queries::SecurityCenter::SecretScanningQuery::PUBLICLY_LEAKED_TRUE_ENUM)
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_multi_repo!(request_hash)
      included = parsed_query.multi_repository_enums
      return unless included.present?

      GitHub.logger.info(
        "filter for multi-repository alerts requested on secret scanning index page",
        "service.name": self.class.name,
        "strategy.name": strategy.class.name,
        "user.id": current_user.id,
        "query": parsed_query.query.to_s,
        "multi_repo.included": included,
      )

      request_hash[:multi_repo] = included.include?(Search::Queries::SecurityCenter::SecretScanningQuery::MULTI_REPOSITORY_TRUE_ENUM)
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_security_campaign_ids!(request_hash)
      return unless @security_campaign_ids.present?

      GitHub.logger.info(
        "filter for security campaign ids requested on secret scanning index page",
        "service.name": self.class.name,
        "strategy.name": strategy.class.name,
        "user.id": current_user.id,
        "query": parsed_query.query.to_s,
        "security_campaign_ids": @security_campaign_ids,
      )

      request_hash[:campaign_filter] = {
        include: {
          campaign_ids: @security_campaign_ids
        }
      }
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_results_category!(request_hash)
      raise InvalidQueryError if parsed_query.has_invalid_results_category?
      request_hash[:low_confidence] = parsed_query.results_category == Search::Queries::SecurityCenter::SecretScanningQuery::GENERIC_RESULTS
    end

    def with_sort!(request_hash)
      request_hash[:sort_order] = parsed_query.sort_enum
    end

    def with_paging!(request_hash, page, per_page)
      request_hash[:page] = page
      request_hash[:limit] = per_page
    end

    # Attach cursor-based paging parameters. Raises InvalidQueryError if both cursors provided.
    sig { params(request_hash: T::Hash[Symbol, T.untyped], before_cursor: T.nilable(String), after_cursor: T.nilable(String)).void }
    def with_cursor_paging!(request_hash, before_cursor, after_cursor)
      return if before_cursor.nil? && after_cursor.nil?
      raise InvalidQueryError, "Cannot specify both before_cursor and after_cursor parameters" if before_cursor.present? && after_cursor.present?

      request_hash[:previous_cursor] = before_cursor unless before_cursor.nil?
      request_hash[:next_cursor] = after_cursor unless after_cursor.nil?
    end

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_assignees!(request_hash)
      assignee_login = parsed_query.assignee_login
      excluded_assignee_login = parsed_query.excluded_assignee_login
      assigned_user_presence = parsed_query.assigned_user_presence

      return unless assignee_login.present? || excluded_assignee_login.present? || assigned_user_presence.present?

      assignee_filter = {}

      if assignee_login.present?
        user_id = resolve_user_id(assignee_login)
        assignee_filter[:assigned_user_id] = user_id if user_id.present?
      elsif excluded_assignee_login.present?
        excluded_user_id = resolve_user_id(excluded_assignee_login)
        assignee_filter[:excluded_assigned_user_id] = excluded_user_id if excluded_user_id.present?
      end

      if assigned_user_presence.present?
        assignee_filter[:assigned_user_presence] = assigned_user_presence
      end

      request_hash[:assignee_filter] = GitHub::Proto::SecretScanning::Api::V2::AssigneeFilter.new(assignee_filter) unless assignee_filter.empty?
    end

    sig { params(login: String).returns(T.nilable(Integer)) }
    def resolve_user_id(login)
      # Handle @me macro - replace with current user's login
      resolved_login = login == "@me" ? current_user.display_login : login

      # Look up user ID from login
      user = User.find_by(login: resolved_login)

      return nil unless user.present?

      user.id
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

    sig { params(request_hash: T::Hash[Symbol, T.untyped]).void }
    def with_campaign_states!(request_hash)
      return unless parsed_query.campaign_enums.present? || parsed_query.negated_campaign_enums.present?
      included, excluded = net_qualifier_values(parsed_query.campaign_enums, parsed_query.negated_campaign_enums).values_at(:included, :excluded)
      return unless included.present? || excluded.present?

      org = if strategy.is_a?(RepositoryScopeStrategy)
        T.cast(strategy, RepositoryScopeStrategy).repository.organization
      elsif strategy.is_a?(OrganizationScopeStrategy)
        T.cast(strategy, OrganizationScopeStrategy).organization
      end

      campaign_filter = parsed_query.build_campaigns_request(organization: org, current_user: current_user, included: included, excluded: excluded)

      GitHub.logger.info(
        "campaign filter requested on secret scanning index page",
        "service.name": self.class.name,
        "strategy.name": strategy.class.name,
        "user.id": current_user.id,
        "org.id": org&.id,
        "query": parsed_query.query.to_s,
      )
      request_hash[:campaign_filter] = campaign_filter
    end
  end
end

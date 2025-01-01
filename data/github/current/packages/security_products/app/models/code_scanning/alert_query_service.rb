# typed: true
# frozen_string_literal: true

require "turboscan"

module CodeScanning
  ##
  # Domain service for fetching code scanning alerts and filters from turboscan.
  class AlertQueryService
    extend T::Sig
    include GitHub::SecurityCenter::TenantFilteringHelper

    ##
    # Indicates that query will effectively lead to empty result due to conflicting filters.
    class EmptyResultError < StandardError; end

    sig do
      params(
        user: User,
        user_session: UserSession,
        organizations: T.any(T::Array[Organization], ActiveRecord::Relation), # Organizations in the business accessible to the user
        business: Business,
        query: T.nilable(String),
        visibility: T.any(T.nilable(String), T::Array[String])
      ).returns(CodeScanning::AlertQueryService)
    end
    def self.for_business(user:, user_session:, organizations:, business:, query: nil, visibility: nil)
      parsed_query = Search::Queries::SecurityCenter::CodeScanningBusinessQuery.new(query)
      strategy = BusinessScopeStrategy.new(
        user: user,
        user_session: user_session,
        organizations: organizations,
        business: business,
        parsed_query: parsed_query
      )

      new(parsed_query: parsed_query, strategy: strategy, visibility: visibility)
    end

    sig do
      params(
        user: User,
        user_session: UserSession,
        organization: Organization,
        allowed_repository_ids: T.nilable(T::Array[Integer]), # IDs for repositories the user is allowed to access. If nil, the user has access to all repositories.
        query: T.nilable(String),
        visibility: T.any(T.nilable(String), T::Array[String]) # the repository visibility all results should be filtered by
      ).returns(CodeScanning::AlertQueryService)
    end
    def self.for_organization(user:, user_session:, organization:, allowed_repository_ids: nil, query: nil, visibility: nil)
      parsed_query = Search::Queries::SecurityCenter::CodeScanningOrgQuery.new(query)
      strategy = OrganizationScopeStrategy.new(
        user: user,
        user_session: user_session,
        organization: organization,
        parsed_query: parsed_query,
        allowed_repository_ids: allowed_repository_ids
      )

      new(parsed_query: parsed_query, strategy: strategy, visibility: visibility)
    end

    sig do
      params(
        user: User,
        user_session: UserSession,
        repository: Repository,
        query: T.nilable(String),
        visibility: T.any(T.nilable(String), T::Array[String]) # the repository visibility all results should be filtered by
      ).returns(CodeScanning::AlertQueryService)
    end
    def self.for_repository(user:, user_session:, repository:, query: nil, visibility: nil)
      parsed_query = Search::Queries::SecurityCenter::CodeScanningRepoQuery.new(query)
      strategy = RepositoryScopeStrategy.new(
        user: user,
        user_session: user_session,
        repository: repository,
      )

      new(parsed_query: parsed_query, strategy: strategy, visibility: visibility)
    end

    sig { returns(ScopeStrategy) }
    attr_reader :strategy

    private_class_method :new

    ##
    # Creates class instance
    sig do
      params(
        parsed_query: Search::Queries::SecurityCenter::CodeScanningBaseQuery, # pass a subclass of this
        strategy: CodeScanning::AlertQueryService::ScopeStrategy,
        visibility: T.any(T.nilable(String), T::Array[String])
      ).void
    end
    def initialize(parsed_query:, strategy:, visibility: nil)
      @parsed_query = parsed_query
      @strategy = strategy
      @visibility = visibility
    end

    ##
    # Fetches alerts for the specified repositories.
    #
    # @param page [Number] the current page index, 1-based
    # @param per_page [Number] the number of items to return per-page
    # @return Array<Array<CodeScanning::AlertResult>, Number, Number, Boolean>
    #   Array<CodeScanning::AlertResult> repository alerts
    #   Number                           number of open alerts
    #   Number                           number of closed alerts
    #   Boolean                          indicates backend request success/failure
    def alerts_by_repo(page: 1, per_page: 25)
      alert_results, repos_by_id, has_error, response = alerts_by_repo_with_response(page:, per_page:)

      open_count = response.try(:data).try(:open_count) || 0
      closed_count = response.try(:data).try(:resolved_count) || 0

      [alert_results, repos_by_id, open_count, closed_count, has_error]
    end

    # The same as alerts_by_repo but instead of returning some fields from the response, this returns the full
    # Turboscan response.
    #
    # @param before_cursor [String, nil] the cursor to fetch the previous page
    # @param after_cursor [String, nil] the cursor to fetch the next page
    # @param page [Number] the current page index, 1-based
    # @param per_page [Number] the number of items to return per-page
    # @param repo_numbers [Array<Turboscan::Proto::RepoNumber>] the repository numbers to filter by
    # @return Array<Array<CodeScanning::AlertResult>, Hash<Integer, Repository>, Twirp::ClientResp<AlertsByRepoResponse>>
    #   Array<CodeScanning::AlertResult>         repository alerts
    #   Hash<Integer, Repository>                repositories by id
    #   Boolean                                  indicates backend request success/failure
    #   Twirp::ClientResp<AlertsByRepoResponse>  the full Turboscan response
    def alerts_by_repo_with_response(page: nil, before_cursor: nil, after_cursor: nil, per_page: 25, repo_numbers: nil)
      empty_response = [[], {}, false, nil]
      return empty_response unless has_access_to_any_repo_alert?

      request_hash = {}
      begin
        with_owner_ids!(request_hash)
        with_repository_ids!(request_hash)
        with_excluded_resolutions!(request_hash)
        with_excluded_rule_sarif_identifiers!(request_hash)
        with_excluded_severities!(request_hash)
        with_excluded_tools!(request_hash)
        with_limit!(request_hash, per_page)
        with_paging!(request_hash, page)
        with_cursor_paging!(request_hash, before_cursor, after_cursor)
        with_resolutions!(request_hash)
        with_rule_sarif_identifiers!(request_hash)
        with_search_query!(request_hash)
        with_severities!(request_hash)
        with_sort!(request_hash)
        with_state!(request_hash)
        with_tools!(request_hash)
        with_repo_numbers!(request_hash, repo_numbers)
        with_repository_visibility!(request_hash)
        with_classification!(request_hash)
      rescue EmptyResultError
        return empty_response
      end

      response = GitHub::Turboscan.alerts_by_repo(Turboscan::Proto::AlertsByRepoRequest.new(request_hash).to_h)

      has_error = response.nil? || response.error.present?

      repo_alerts, repos_by_id = filter_tenant_rows(
        @strategy.tenant_filter_scope,
        response.try(:data).try(:results) || [],
        -> (repo) { repo.repository_id }
      )

      alert_results = repo_alerts.map do |r|
        CodeScanning::AlertResult.new(repository: repos_by_id[r.repository_id], result: r.result)
      end

      [alert_results, repos_by_id, has_error, response]
    end

    sig { returns(T::Array[Turboscan::Proto::RepositoryIDsResponse::Repository]) }
    def repository_ids_for_repo_menu
      empty_response = []
      return empty_response unless has_access_to_any_repo_alert?

      request_hash = {}
      begin
        with_owner_ids!(request_hash)
        with_alerts_filter!(request_hash)
        with_repository_ids!(request_hash, exclude_filter_type: :repo)
      rescue EmptyResultError
        return empty_response
      end

      repository_ids_for_org(request_hash)
    end

    def repository_ids_from_filters
      empty_response = []
      return empty_response unless has_access_to_any_repo_alert?

      request_hash = {}
      begin
        with_owner_ids!(request_hash)
        with_alerts_filter!(request_hash)
        with_repository_ids!(request_hash)
      rescue EmptyResultError
        return empty_response
      end

      repository_ids_for_org(request_hash)
    end

    ##
    # Fetches an aggregated list of rules from alerts
    sig { params(search_query: T.nilable(String)).returns(T::Array[Turboscan::Proto::OrgRule]) }
    def rules_for_org(search_query = nil)
      return [] unless has_access_to_any_repo_alert?

      request_hash = {}
      begin
        with_owner_ids!(request_hash)
        with_alerts_filter!(request_hash, search_query, exclude_filter_type: :rule)
        with_repository_ids!(request_hash)
      rescue EmptyResultError
        return []
      end

      response = GitHub::Turboscan.rules_for_org(Turboscan::Proto::RulesForOrgRequest.new(request_hash).to_h)
      response.try(:data).try(:rules).to_a || []
    end

    def selected_organizations
      @strategy.try(:selected_organizations)
    end

    ##
    # Fetches an aggregated list of severities from alerts
    #
    # @return Array<Turboscan::Proto::SeveritiesForOrgResponse::SeverityItem>
    def severities_for_org(applies_severity_filter: false)
      return [] unless has_access_to_any_repo_alert?

      request_hash = {}
      begin
        with_owner_ids!(request_hash)
        exclude_filter_type = applies_severity_filter ? nil : :severity
        with_alerts_filter!(request_hash, exclude_filter_type: exclude_filter_type)
        with_repository_ids!(request_hash)
      rescue EmptyResultError
        return []
      end

      response = GitHub::Turboscan.severities_for_org(Turboscan::Proto::SeveritiesForOrgRequest.new(request_hash).to_h)
      response.try(:data).try(:severities) || []
    end

    ##
    # Fetches an aggregated list of tools from alerts
    #
    # @return Array<Turboscan::Proto::ToolDescription>
    def tool_names_for_org
      return [] unless has_access_to_any_repo_alert?

      request_hash = {}
      begin
        with_owner_ids!(request_hash)
        with_alerts_filter!(request_hash, exclude_filter_type: :tool)
        with_repository_ids!(request_hash)
      rescue EmptyResultError
        return []
      end

      response = GitHub::Turboscan.tool_names_for_org(Turboscan::Proto::ToolNamesForOrgRequest.new(request_hash).to_h)
      response.try(:data).try(:tools) || []
    end

    # @param exclude_filter_type [Symbol, nil] One of :rule, :severity, :tool, or nil.
    def build_alerts_filter(search_query = nil, exclude_filter_type: nil)
      alerts_filter = {}

      with_search_query!(alerts_filter)
      with_state!(alerts_filter)

      with_rule_sarif_identifiers!(alerts_filter) unless exclude_filter_type == :rule
      with_excluded_rule_sarif_identifiers!(alerts_filter)

      with_tools!(alerts_filter) unless exclude_filter_type == :tool
      with_excluded_tools!(alerts_filter)

      with_severities!(alerts_filter) unless exclude_filter_type == :severity
      with_excluded_severities!(alerts_filter)

      with_resolutions!(alerts_filter)
      with_excluded_resolutions!(alerts_filter)

      with_repository_visibility!(alerts_filter)

      with_classification!(alerts_filter)

      if search_query.present?
        alerts_filter[:search_query] = "*#{search_query}*" # make it a wildcard search
      end

      Turboscan::Proto::AlertsFilter.new(alerts_filter)
    end

    private

    ##
    # Fetches repository IDs for the organizations.
    sig { params(request_hash: T::Hash[Symbol, T.untyped]).returns(T::Array[Turboscan::Proto::RepositoryIDsResponse::Repository]) }
    def repository_ids_for_org(request_hash)
      empty_response = []

      response = GitHub::Turboscan.repository_ids_for_org(
        Turboscan::Proto::RepositoryIDsForOrgRequest.new(request_hash).to_h
      )

      if response.nil? || response.error.present?
        log_turboscan_error(:repository_ids_for_org)
        return empty_response
      end

      turboscan_repos, _ = filter_tenant_rows(
        @strategy.tenant_filter_scope,
        response.try(:data).try(:repositories) || [],
        -> (repo) { repo.repository_id }
      )

      turboscan_repos
    end

    def has_access_to_any_repo_alert?
      allowed_repository_ids = @strategy.try(:allowed_repository_ids)
      allowed_repository_ids.nil? || allowed_repository_ids.any?
    end

    def log_turboscan_error(turboscan_method)
      GitHub.dogstats.increment("turboscan_service_error", tags: [
        "turboscan_method_name:#{turboscan_method}",
        "scope:#{@strategy.scope}",
      ])
      Failbot.report(
        StandardError.new("GitHub::Turboscan.#{turboscan_method} failed"),
        "gh.entity.type": @strategy.scope,
        "gh.entity.id": @strategy.tenant_id,
        "gh.entity.name": @strategy.tenant_name
      )
    end

    # @param exclude_filter_type [Symbol, nil] One of :rule, :severity, :tool, or nil.
    def with_alerts_filter!(hash, search_query = nil, exclude_filter_type: nil)
      hash[:filter] = build_alerts_filter(search_query, exclude_filter_type:).to_h
    end

    def with_repository_ids!(hash, exclude_filter_type: nil)
      @strategy.with_repository_ids!(hash, exclude_filter_type: exclude_filter_type)
    end

    def with_excluded_resolutions!(hash)
      hash[:excluded_resolutions] = @parsed_query.excluded_resolution_enums
    end

    def with_excluded_rule_sarif_identifiers!(hash)
      hash[:excluded_rule_sarif_identifiers] = @parsed_query.excluded_rule_sarif_identifiers
    end

    def with_excluded_severities!(hash)
      hash[:excluded_severities] = @parsed_query.excluded_severity_enums
    end

    def with_excluded_tools!(hash)
      hash[:excluded_tools] = @parsed_query.excluded_tools
    end

    def with_owner_ids!(request_hash)
      @strategy.with_owner_ids!(request_hash)
    end

    def with_paging!(hash, page)
      hash.merge!({ numeric_page: page || 1 })
    end

    def with_cursor_paging!(hash, before_cursor, after_cursor)
      hash.merge!({ before_cursor: before_cursor || "", after_cursor: after_cursor || "" })
    end

    def with_limit!(hash, per_page)
      hash.merge!({ limit: per_page })
    end

    def with_resolutions!(hash)
      hash[:resolutions] = @parsed_query.resolution_enums
    end

    def with_rule_sarif_identifiers!(hash)
      hash[:rule_sarif_identifiers] = @parsed_query.rule_sarif_identifiers
    end

    def with_search_query!(hash)
      hash[:search_query] = @parsed_query.search_query
    end

    def with_severities!(hash)
      hash[:severities] = @parsed_query.severity_enums
    end

    def with_sort!(hash)
      hash[:sort_order] = @parsed_query.sort_enum
    end

    def with_state!(hash)
      hash[:state] = if @parsed_query.show_all_states?
        ::Turboscan::Proto::AlertStateFilter::ALERT_STATE_FILTER_ALL
      else
        @parsed_query.alert_state_enums.last
      end
    end

    def with_tools!(hash)
      hash[:tools] = @parsed_query.tools
    end

    def with_repo_numbers!(hash, repo_numbers)
      hash[:repo_numbers] = repo_numbers
    end

    # We may choose to allow filtering by repository visibility in the future.
    # This is so that we can filter out internal/pirvate repositories when the
    # request is made by an org that is part of an enterprise without GHAS.
    def with_repository_visibility!(hash)
      return if @visibility.nil? || @visibility.empty?
      hash[:repository_visibilities] = Array(@visibility).map { |visibility| GitHub::Turboscan.to_repository_visibility(visibility) }.compact
    end

    def with_classification!(hash)
      hash[:classification] = @parsed_query.classification_enum
    end
  end
end

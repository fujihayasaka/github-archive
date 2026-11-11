# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RulesController < Repos::CodeQuality::BaseRepositoryController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Iam,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    only: [:index, :show]

  before_action :ensure_feature_code_quality_enabled
  before_action :check_code_quality_read

  class ShowPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repoCodeQualityShowRoute"
    end

    sig do
      params(
      owner: String,
      repo: String,
      default_branch: String,
      branch_list_cache_key: String,
      rule_id: String,
      rule_title: String,
      rule_description: String,
      rule_help: String,
      rule_category: String,
      rule_severity: String,
      rule_language: String,
      last_scan_at: Google::Protobuf::Timestamp,
      can_autofix: T::Boolean,
      can_dismiss: T::Boolean,
      has_repo_write_access: T::Boolean,
      ).void
    end
    def initialize(
      owner,
      repo,
      default_branch,
      branch_list_cache_key,
      rule_id,
      rule_title,
      rule_description,
      rule_help,
      rule_category,
      rule_severity,
      rule_language,
      last_scan_at,
      can_autofix,
      can_dismiss,
      has_repo_write_access
    )
      @owner = owner
      @repo = repo
      @default_branch = default_branch
      @branch_list_cache_key = branch_list_cache_key
      @rule_id = rule_id
      @rule_title = rule_title
      @rule_description = rule_description
      @rule_help = rule_help
      @rule_category = rule_category
      @rule_severity = rule_severity
      @rule_language = rule_language
      @last_scan_at = last_scan_at
      @can_autofix = can_autofix
      @can_dismiss = can_dismiss
      @has_repo_write_access = has_repo_write_access
    end

    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def payload
      {
        owner: @owner,
        repo: @repo,
        defaultBranch: @default_branch,
        branchListCacheKey: @branch_list_cache_key,
        ruleId: @rule_id,
        ruleTitle: @rule_title,
        ruleDescription: @rule_description,
        ruleHelp: @rule_help,
        ruleCategory: @rule_category,
        ruleSeverity: @rule_severity,
        ruleLanguage: @rule_language,
        lastScanAt: @last_scan_at,
        canAutofix: @can_autofix,
        canDismiss: @can_dismiss,
        hasRepoWriteAccess: @has_repo_write_access,
      }
    end
  end

  sig { void }
  def index
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    query = Search::Queries::CodeQualityRulesQuery.new(params[:query].try(:to_str) || "")

    unless query.is_valid?
      return render json: {
        rules: [],
        count: 0,
        lastScan: nil,
        prevCursor: nil,
        nextCursor: nil,
      }, status: :ok
    end

    sort = prepare_sort
    return sort if sort.is_a?(String)

    response = GitHub::Turboquality.client.get_rules(Turboquality::Proto::GetRulesRequest.new(
      repository_id: current_repository.id,
      page_size: DEFAULT_PER_PAGE,
      before_cursor:,
      after_cursor:,
      filter: build_rules_filter(query),
      sort_order: sort,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    rules = response.data.rules
    last_scan = response.data.last_scan

    payload = {
      rules: serialized_rules(rules.to_a),
      count: response.data.count,
      lastScan: {
        commitOid: last_scan&.commit_oid,
        timestamp: last_scan&.timestamp&.to_time&.utc&.iso8601
      },
      prevCursor: response.data.prev_cursor,
      nextCursor: response.data.next_cursor,
    }

    log_rules_index_analytics_event(query: query)

    render json: payload, status: :ok
  end

  sig { void }
  def show
    response = GitHub::Turboquality.client.get_rule(Turboquality::Proto::GetRuleRequest.new(
      repository_id: current_repository.id,
      rule_id: params[:rule_id]
    ))

    # not_found is only returned if the rule_id is not found
    return render_404 if response.error&.code == :not_found
    raise StandardError.new(response.error.to_s) if response.error

    rule = response.data.rule
    return render_404 if rule.nil?

    last_scan = response.data.last_scan
    return render_404 if last_scan.nil? || last_scan.timestamp.nil?
    last_scan_at = T.must(last_scan.timestamp)

    code_quality_permissions = CodeQualityRepositoryPermissions.new(current_repository)

    payload = ShowPayload.new(
      current_repository.owner.display_login,
      current_repository.name,
      current_repository.default_branch,
      helpers.ref_list_cache_key(repository: current_repository),
      rule.rule_id,
      rule.title,
      rule.description,
      rule.rule_help,
      serialized_category(rule.category),
      serialized_severity(rule.severity),
      serialized_language(rule.language),
      last_scan_at,
      code_quality_permissions.code_quality_writable_by?(current_user),
      code_quality_permissions.code_quality_writable_by?(current_user),
      current_repository.writable_by?(current_user)
    )

    respond_with_react(
      title: "Code quality · #{rule.title}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_container",
    )
  end

  private

  sig { params(rules: T::Array[Turboquality::Proto::Rule]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_rules(rules)
    rules.map do |rule|
      {
        ruleId: rule.rule_id,
        title: rule.title,
        description: rule.description,
        openCount: rule.open_count,
        dismissedCount: rule.dismissed_count,
        severity: serialized_severity(rule.severity),
        category: serialized_category(rule.category),
        language: serialized_language(rule.language),
      }
    end
  end

  sig { params(severity: T.any(Integer, Symbol)).returns(String) }
  def serialized_severity(severity)
    severity = Turboquality::Proto::RuleSeverity.lookup(severity) if severity.is_a?(Integer)
    severity.to_s.downcase.delete_prefix("sev_")
  end

  sig { params(category: T.any(Integer, Symbol)).returns(String) }
  def serialized_category(category)
    category = Turboquality::Proto::RuleCategory.lookup(category) if category.is_a?(Integer)
    category.to_s.downcase.delete_prefix("cat_")
  end

  sig { params(language: T.any(Integer, Symbol)).returns(String) }
  def serialized_language(language)
    language = Turboquality::Proto::RuleLanguage.lookup(language) if language.is_a?(Integer)
    language.to_s.downcase.delete_prefix("rule_language_")
  end

  SORT = T.let({
    "alpha" => {
      "asc" => :RULES_SORT_ORDER_ALPHABETICAL_ASCENDING,
      "desc" => :RULES_SORT_ORDER_ALPHABETICAL_DESCENDING,
    }.freeze,
    "count" => {
      "asc" => :RULES_SORT_ORDER_NUMBER_OF_FINDINGS_ASCENDING,
      "desc" => :RULES_SORT_ORDER_NUMBER_OF_FINDINGS_DESCENDING,
    }.freeze,
    "severity" => {
      "asc" => :RULES_SORT_ORDER_SEVERITY_ASCENDING,
      "desc" => :RULES_SORT_ORDER_SEVERITY_DESCENDING,
    }.freeze,
  }.freeze, T::Hash[String, T::Hash[String, Symbol]])

  sig { returns(T.any(T.nilable(Symbol), String)) }
  def prepare_sort
    sort_by = params[:sort_by].try(:to_str)
    sort_order = params[:sort_order].try(:to_str) || "desc"

    return nil if sort_by.nil?

    sort_by_options = SORT[sort_by]
    if sort_by_options.nil?
      return render status: 400, json: { error: "Invalid sort_by parameter. Valid options are: #{SORT.keys.sort.join(', ')}" }
    end

    sort = sort_by_options[sort_order]
    if sort.nil?
      return render status: 400, json: { error: "Invalid sort_order parameter. Valid options are: asc, desc" }
    end

    sort
  end

  sig { params(query: Search::Queries::CodeQualityRulesQuery).returns(Turboquality::Proto::RulesFilter) }
  def build_rules_filter(query)
    Turboquality::Proto::RulesFilter.new(
      finding_state: query.finding_state_filter,
      category: query.category_filter,
      severity: query.severity_filter,
      language: query.language_filter,
      name: query.rule_name_filter,
    )
  end

  sig do
    params(
      query: Search::Queries::CodeQualityRulesQuery,
    ).void
  end
  def log_rules_index_analytics_event(query:)
    sort_by = params[:sort_by].try(:to_str)
    sort_order = sort_by.nil? ? nil : (params[:sort_order].try(:to_str) || "desc")

    analytics_event(
      category: "code_quality",
      action: "get_repo_rules",
      label: {
        repository_id: current_repository.id,
        org_id: current_repository.owner_id,
        finding_state_filters: query.finding_state,
        category_filters: query.category,
        severity_filters: query.severity,
        language_filters: query.language,
        has_rule_name_query: query.rule_name_filter.present?,
        sort_by:,
        sort_order:,
      },
    )
  end
end

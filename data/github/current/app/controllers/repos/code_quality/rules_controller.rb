# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RulesController < Repos::CodeQuality::BaseRepositoryController

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesPushes,
    only: [:index, :show]

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
      can_dismiss
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
      }
    end
  end

  sig { void }
  def index
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    severity = prepare_severity
    return severity if severity.is_a?(String)

    category = prepare_category
    return category if category.is_a?(String)

    language = prepare_language
    return language if language.is_a?(String)

    response = GitHub::Turboquality.client.rule_results(Turboquality::Proto::RuleResultsRequest.new(
      repository_id: current_repository.id,
      page_size: DEFAULT_PER_PAGE,
      before_cursor:,
      after_cursor:,
      category:,
      severity:,
      language:,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    rules = response.data.rules
    payload = {
      rules: serialized_rules(rules.to_a),
      count: response.data.count,
      prevCursor: response.data.prev_cursor,
      nextCursor: response.data.next_cursor,
    }
    render json: payload, status: :ok
  end

  sig { void }
  def show
    response = GitHub::Turboquality.client.rule_results(Turboquality::Proto::RuleResultsRequest.new(
      repository_id: current_repository.id,
      rule_id: params[:rule_id]
    ))
    # not_found is only returned if the rule_id is not found
    return render_404 if response.error&.code == :not_found
    raise StandardError.new(response.error.to_s) if response.error

    rules = response.data.rules.to_a

    return render_404 if rules.length == 0
    raise StandardError.new("Did not expect more than 1 rule results") if rules.length > 1

    code_quality_permissions = CodeQualityRepositoryPermissions.new(current_repository)

    rule = T.must(rules[0])
    last_scan_at = T.must(response.data.last_scan_at)
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
    )

    respond_with_react(
      title: "Code quality · #{rule.title}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_container",
    )
  end

  private

  sig { params(rules: T::Array[Turboquality::Proto::RuleResult]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_rules(rules)
    rules.map do |rule|
      {
        ruleId: rule.rule_id,
        title: rule.title,
        description: rule.description,
        findingsCount: rule.result_count,
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

  sig { returns(T.any(T.nilable(Integer), String)) }
  def prepare_severity
    severity = params[:severity]
    return nil if severity.nil?

    severity = GitHub::Turboquality.to_rule_severity(severity)
    if severity.nil?
      return render status: 400, json: { error: "Invalid severity parameter" }
    end

    severity
  end

  sig { returns(T.any(T.nilable(Integer), String)) }
  def prepare_category
    category = params[:category]
    return nil if category.nil?

    category = GitHub::Turboquality.to_rule_category(category)
    if category.nil?
      return render status: 400, json: { error: "Invalid category parameter" }
    end

    category
  end

  sig { returns(T.any(T.nilable(Integer), String)) }
  def prepare_language
    language = params[:language]
    return nil if language.nil?

    language = GitHub::Turboquality.to_rule_language(language)
    if language.nil?
      return render status: 400, json: { error: "Invalid language parameter" }
    end

    language
  end
end

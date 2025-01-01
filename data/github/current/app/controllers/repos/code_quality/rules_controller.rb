# typed: strict
# frozen_string_literal: true

class Repos::CodeQuality::RulesController < Repos::CodeQuality::BaseRepositoryController
  include ScanningControllerMethods

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
    only: [:index, :show]

  before_action :check_code_scanning_read

  class ShowPayload < ReactPayload::Base
    sig { override.returns(String) }
    def route_id
      "repoCodeQualityShowRoute"
    end

    sig do
      params(
      owner: String,
      repo: String,
      rule_id: String,
      rule_title: String,
      rule_description: String,
      rule_help: String,
      rule_category: String,
      rule_severity: String,
      last_scan_at: Google::Protobuf::Timestamp,
      file_count: Integer,
      ).void
    end
    def initialize(
      owner,
      repo,
      rule_id,
      rule_title,
      rule_description,
      rule_help,
      rule_category,
      rule_severity,
      last_scan_at,
      file_count
    )
      @owner = owner
      @repo = repo
      @rule_id = rule_id
      @rule_title = rule_title
      @rule_description = rule_description
      @rule_help = rule_help
      @rule_category = rule_category
      @rule_severity = rule_severity
      @last_scan_at = last_scan_at
      @file_count = file_count
    end

    sig { override.returns(T::Hash[String, T.untyped]) }
    def payload
      {
        owner: @owner,
        repo: @repo,
        ruleId: @rule_id,
        ruleTitle: @rule_title,
        ruleDescription: @rule_description,
        ruleHelp: @rule_help,
        ruleCategory: @rule_category,
        ruleSeverity: @rule_severity,
        lastScanAt: @last_scan_at,
        fileCount: @file_count,
      }
    end
  end

  sig { void }
  def index
    after_cursor = params[:after].try(:to_str)
    before_cursor = params[:before].try(:to_str)

    response = GitHub::Turboquality.client.rule_results(Turboquality::Proto::RuleResultsRequest.new(
      repository_id: current_repository.id,
      page_size: DEFAULT_PER_PAGE,
      before_cursor:,
      after_cursor:,
    ))
    raise StandardError.new(response.error.to_s) if response.error

    rules = response.data.rules
    payload = {
      rules: serialized_rules(rules.to_a),
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
    raise StandardError.new(response.error.to_s) if response.error

    rules = response.data.rules.to_a

    return render_404 if rules.length == 0
    raise StandardError.new("Did not expect more than 1 rule results") if rules.length > 1

    rule = T.must(rules[0])
    last_scan_at = T.must(response.data.last_scan_at)
    file_count = rule.file_count
    payload = ShowPayload.new(
      current_repository.owner.display_login,
      current_repository.name,
      rule.rule_id,
      rule.title,
      rule.description,
      rule.rule_help,
      serialized_category(rule.category),
      serialized_severity(rule.severity),
      last_scan_at,
      file_count,
    )

    render_react_html(
      title: "Code quality · #{rule.title}",
      app_name: "code-quality",
      payload:,
      layout: "layouts/code_quality/repositories_container",
    )
  end

  private

  sig { params(rules: T::Array[Turboquality::Proto::RuleResults]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def serialized_rules(rules)
    rules.map do |rule|
      {
        ruleId: rule.rule_id,
        title: rule.title,
        description: rule.description,
        findingsCount: rule.result_count,
        severity: serialized_severity(rule.severity),
        category: serialized_category(rule.category),
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
end

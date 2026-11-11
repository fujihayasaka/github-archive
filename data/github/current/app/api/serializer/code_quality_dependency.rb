# typed: strict
# frozen_string_literal: true

module Api::Serializer::CodeQualityDependency
  extend T::Helpers
  requires_ancestor { Api::Serializer::RepositoriesDependency }

  sig { params(findings: T::Hash[Symbol, T.untyped], options: T.untyped).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def code_quality_findings_hash(findings, options = {})
    repo = T.let(options[:repo], Repository)
    findings_list = T.let(findings.fetch(:findings, []), T::Array[Turboquality::Proto::Finding])
    findings_list.map do |finding|
      code_quality_finding_base_hash(finding, repo: repo, serialize_login: options[:serialize_login], include_help: false)
    end
  end

  sig { params(finding: Turboquality::Proto::Finding, options: T.untyped).returns(T::Hash[Symbol, T.untyped]) }
  def code_quality_finding_hash(finding, options = {})
    repo = T.let(options[:repo], Repository)
    code_quality_finding_base_hash(finding, repo: repo, serialize_login: options[:serialize_login], include_help: true)
  end

  private

  sig { params(finding: Turboquality::Proto::Finding, repo: Repository, serialize_login: T.untyped, include_help: T::Boolean).returns(T::Hash[Symbol, T.untyped]) }
  def code_quality_finding_base_hash(finding, repo:, serialize_login: nil, include_help: true)
    rule = T.must(finding.rule)
    location = T.must(finding.location)

    finding_state = finding.finding_state
    finding_state = Turboquality::Proto::FindingState.resolve(finding_state) if finding_state.is_a?(Symbol)

    rule_hash = {
      id: rule.rule_id,
      title: rule.title,
      description: rule.description,
      severity: code_quality_severity(rule.severity),
      category: code_quality_category(rule.category),
    }
    rule_hash[:help] = rule.rule_help if include_help

    {
      number: finding.number,
      state: if finding_state == Turboquality::Proto::FindingState::FINDING_STATE_OPEN
               "open"
             else
               "dismissed"
             end,
      url: url("/repos/#{repo.name_with_owner_for_api(use: serialize_login)}/code-quality/findings/#{finding.number}"),
      rule: rule_hash,
      location: code_quality_location_hash(location),
      message: code_quality_message_hash(finding),
      created_at: time(finding.created_at),
    }
  end

  public

  sig { params(location: Turboquality::Proto::Location).returns(T::Hash[Symbol, T.untyped]) }
  def code_quality_location_hash(location)
    {
      path: location.file_path,
      start_line: location.start_line,
      end_line: location.end_line,
      start_column: location.start_column,
      end_column: location.end_column,
    }
  end

  sig { params(finding: Turboquality::Proto::Finding).returns(T::Hash[Symbol, T.untyped]) }
  def code_quality_message_hash(finding)
    text = ::CodeScanning::AlertMessagePlaceholderLinks.strip_placeholder_links(finding.message)
    markdown = ::CodeScanning::AlertMessagePlaceholderLinks.replace_placeholder_links(
      finding.message,
      related_locations: finding.related_locations,
    )

    {
      text:,
      markdown:,
    }
  end

  sig { params(severity: T.any(Integer, Symbol)).returns(String) }
  def code_quality_severity(severity)
    severity = Turboquality::Proto::RuleSeverity.lookup(severity) if severity.is_a?(Integer)
    severity.to_s.downcase.delete_prefix("sev_")
  end

  sig { params(category: T.any(Integer, Symbol)).returns(String) }
  def code_quality_category(category)
    category = Turboquality::Proto::RuleCategory.lookup(category) if category.is_a?(Integer)
    category.to_s.downcase.delete_prefix("cat_")
  end
end

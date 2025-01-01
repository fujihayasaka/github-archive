# typed: true
# frozen_string_literal: true

module CodeScanningHelper
  include TextHelper

  SORT_OPTIONS = [
    { label: "Newest", query: "created-desc" },
    { label: "Oldest", query: "created-asc" },
    { label: "Recently updated", query: "updated-desc" },
    { label: "Least recently updated", query: "updated-asc" },
  ].freeze

  RESOLUTION_OPTIONS = [
    { label: "All dismissed", query: "dismissed" },
    { label: "False positive", query: "false-positive" },
    { label: "Used in tests", query: "used-in-tests" },
    { label: "Won't fix", query: "wont-fix" },
    { label: "Fixed", query: "fixed" }
  ].freeze

  SECURITY_SEVERITIES = [:CRITICAL, :HIGH, :MEDIUM, :LOW].freeze
  SEVERITIES = [:ERROR, :WARNING, :NOTE].freeze

  AUTOFIX_RULES_LANGUAGE_MAP = {
    cpp: "C++",
    cs: "C#",
    go: "Go",
    java: "Java/Kotlin",
    js: "JavaScript/TypeScript",
    py: "Python",
    rb: "Ruby",
    swift: "Swift"
  }

  def alert_closure_reasons
    {
      FALSE_POSITIVE: "False positive",
      USED_IN_TESTS: "Used in tests",
      WONT_FIX: "Won't fix",
    }
  end

  def close_reason_details_singular
    {
      WONT_FIX: "This alert is not relevant",
      FALSE_POSITIVE: "This alert is not valid",
      USED_IN_TESTS: "This alert is not in production code",
    }
  end

  def close_reason_details_plural
    {
      FALSE_POSITIVE: "These alerts are not valid",
      USED_IN_TESTS: "These alerts are not in production code",
      WONT_FIX: "These alerts are not relevant",
    }
  end

  def alert_closure_reason_description(result)
    alert_closure_reasons[result.resolution].downcase
  end

  def alert_resolution_query_value(result)
    return "fixed" if result.is_fixed
    result.resolution.to_s.downcase.gsub("_", "-")
  end

  def display_ref_name(ref_name)
    ref_name = ref_name.dup.force_encoding(Encoding::UTF_8).scrub!
    Git::Ref::COMMON_PREFIXES.each do |prefix|
      if ref_name.start_with?(prefix)
        return ref_name[prefix.size, ref_name.length]
      end
    end
    ref_name
  end

  def classifications_for_alert_instance(alert_instance)
    alert_instance.classification.map { |classification| classification.capitalize }
  end

  def timestamp_to_time(timestamp)
    Time.at(timestamp.nanos * 10**-9 + timestamp.seconds)
  end

  def result_closed?(result)
    result_resolved?(result) || result_fixed?(result)
  end

  def result_resolved?(result)
    result.resolution.present? && result.resolution != :NO_RESOLUTION
  end

  def result_fixed?(result)
    result.is_fixed
  end

  def alerts_writable_by_user?(repository, user)
    return @alerts_writable if defined? @alerts_writable
    @alerts_writable = !repository.archived? && repository.code_scanning_writable_by?(user)
  end

  def result_message_text(result)
    html = GitHub::Goomba::MarkdownPipeline.to_html(result.message_text)
    strip_tags_and_collapse_whitespace(html)
  end

  def result_title(result)
    if result.rule&.short_description.present?
      result.rule.short_description
    else
      result_message_text(result)
    end
  end

  # Todo: Replace this method once we get rid of the view model. It's a placeholder for now.
  def urls
    @urls ||= ViewModel::URLs.new
  end

  def repository_result_path(repository, alert_number)
    urls.repository_code_scanning_result_path(repository.owner, repository, number: alert_number)
  end

  def repository_index_path(repository, **params)
    urls.repository_code_scanning_results_path(repository.owner, repository, params)
  end

  def create_pr_path(repository, result)
    alert_number = result.number
    alert_title = result_title(result)

    urls.repository_code_scanning_autofix_commits_path(repository.owner, repository, alert_number)
  end

  def severity_symbol_for_result(result)
    severity_symbol = if result.security_severity && result.security_severity != :NO_SECURITY_SEVERITY
      result.security_severity
    elsif result.rule_severity && result.rule_severity != :NONE
      result.rule_severity
    end
    severity_symbol
  end

  def severity_link_for_repo_result(repository, result, query)
    severity_symbol = severity_symbol_for_result(result)

    if severity_symbol
      repository_index_path(repository, query: query.toggle_qualifier(name: :severity, value: severity_symbol.to_s.downcase))
    else
      repository_index_path(repository, query: query.query_string)
    end
  end

  sig do
    params(
      results: T::Enumerable[T.any(Turboscan::Proto::Result, Turboscan::Proto::RepoResult, CodeScanning::AlertResult)],
      repository_id: T.nilable(Integer),
    ).returns(T::Hash[T::Array[Integer], T::Array[User]])
  end
  def assignees_by_alert_number_and_repository(results, repository_id: nil)
    results = results.map do |result|
      if result.is_a?(Turboscan::Proto::Result)
        Turboscan::Proto::RepoResult.new(
          repository_id:,
          result:,
        )
      else
        result
      end
    end

    assignee_ids = results.flat_map { |result| T.must(result.result).assigned_user_ids }.uniq
    return {} if assignee_ids.empty?

    assignees_by_id = T.let(User.where(id: assignee_ids).index_by(&:id), T::Hash[Integer, User])

    alert_number_plus_repository_id_to_assignees = results.map do |result|
      assignees = T.must(result.result).assigned_user_ids.filter_map do |user_id|
        assignees_by_id[user_id]
      end
      [[T.must(result.result).number, result.is_a?(CodeScanning::AlertResult) ? result.repository.id : result.repository_id], assignees]
    end.to_h
  end

  def security_severity_symbols
    SECURITY_SEVERITIES
  end

  def severity_symbols
    SEVERITIES
  end

  def repository_index_refs_path(repository, query, **params)
    urls.repository_code_scanning_results_ref_list_path(repository.owner, repository, { query: query.user_query }.merge(params))
  end

  def repository_index_rules_path(repository, query, **params)
    urls.repository_code_scanning_results_rule_list_path(repository.owner, repository, { query: query.user_query }.merge(params))
  end

  def repository_index_tags_path(repository, query, **params)
    urls.repository_code_scanning_results_tag_list_path(repository.owner, repository, { query: query.user_query }.merge(params))
  end

  def repository_index_tools_path(repository, query, **params)
    urls.repository_code_scanning_results_tool_list_path(repository.owner, repository, { query: query.user_query }.merge(params))
  end

  def security_center_code_scanning_tool_list_json_path(organization, query:)
    urls.security_center_code_scanning_tool_list_path(organization, query: query, format: :json)
  end

  def security_center_code_scanning_rule_list_json_path(organization, query:)
    urls.security_center_code_scanning_rule_list_path(organization, query: query, format: :json)
  end

  def security_center_code_scanning_repository_list_json_path(organization, query:)
    urls.security_center_code_scanning_repository_list_path(organization, query: query, format: :json)
  end

  def security_center_code_scanning_tag_list_json_path(organization, query:)
    urls.security_center_code_scanning_tag_list_path(organization, query: query, format: :json)
  end

  def security_center_code_scanning_teams_list_json_path(organization)
    urls.security_center_options_path(organization, "options-type": "teams", format: :json)
  end

  def security_center_code_scanning_topics_list_json_path(organization)
    urls.security_center_options_path(organization, "options-type": "topics", format: :json)
  end

  def security_center_code_scanning_custom_property_list_json_path(organization, custom_property_name)
    urls.security_center_options_path(organization, "options-type": "props", name: custom_property_name, format: :json)
  end

  def security_center_alerts_code_scanning_filter_input_suggestions_enterprise_json_path(business, filter_name:)
    urls.security_center_alerts_code_scanning_filter_input_suggestions_enterprise_path(business, suggestion: filter_name, format: :json)
  end

  def security_center_alerts_code_scanning_options_enterprise_json_path(business, filter_name:)
    urls.security_center_options_enterprise_path(business, "options-type": filter_name, format: :json)
  end

  def show_experimental_query_info_for_tags_and_tool?(alert_rule_tags, alert_tool_name)
    alert_rule_tags&.include?("experimental") &&
    CodeScanning::Tool.canonical_name(alert_tool_name) == "CodeQL"
  end

  def code_scanning_codeql_template_url(repository)
    urls.new_file_path(
      repository.owner,
      repository,
      name: repository.default_branch_ref&.name || "master",
      workflow_template: "code-scanning/codeql",
      filename: ".github/workflows/codeql.yml"
    )
  end
end

# typed: true
# frozen_string_literal: true

class CodeScanning::AlertTableRowComponent < ApplicationComponent
  include CodeScanningHelper
  include ScanningHelper

  attr_reader :repository, :show_checkbox, :show_repository, :show_organization, :repository_result_path, :severity_link, :experimental_tag_path, :show_alert_number, :linked_issues

  def initialize(
    repository:,
    alert:,
    instance:,
    show_checkbox:,
    show_repository:,
    show_organization:,
    linked_issues:,
    show_link_to_issue: false,  # For passing down the show_code_scanning_linked_alerts feature flag
    repository_result_path:,
    severity_link:,
    query:,
    alerts_code_scanning_index_path_method:,
    experimental_tag_path:,
    show_alert_number:
  )

    @repository = repository
    @alert = alert
    @instance = instance
    @show_checkbox = show_checkbox
    @show_repository = show_repository
    @show_organization = show_organization
    @linked_issues = linked_issues
    @show_link_to_issue = show_link_to_issue
    @repository_result_path = repository_result_path
    @severity_link = severity_link
    @query = query
    @alerts_code_scanning_index_path_method = alerts_code_scanning_index_path_method
    @experimental_tag_path = experimental_tag_path
    @show_alert_number = show_alert_number
  end

  private

  def repository_results_path
    repository_code_scanning_results_path(@repository.owner, @repository)
  end

  def alert_title
    result_title(@alert)
  end

  def alert_number
    @alert.number
  end

  def alert_tool
    @alert.tool.name
  end

  def alert_created_at
    @alert.created_at
  end

  def alert_rule_severity
    @alert.rule_severity
  end

  def alert_security_severity
    @alert.security_severity
  end

  def alert_state_timestamp
    return @alert.resolved_at if result_resolved?(@alert)
    return @alert.fixed_at if @alert.is_fixed
    alert_created_at
  end

  def alert_file_path
    @instance.location.file_path
  end

  def alert_file_start_line
    @instance.location.start_line
  end

  def alert_file_branch_ref_name
    display_ref_name(@instance.ref_name_bytes)
  end

  def alert_closed?
    result_resolved?(@alert) || @alert.is_fixed
  end

  def alert_state_icon
    return "shield-check" if alert_closed?
    "shield"
  end

  def alert_state_label
    state = alert_closed? ? "closed" : "opened"
    show_alert_number ? state : state.capitalize
  end

  def alert_closed_reason
    return alert_closure_reason_description(@alert) if result_resolved?(@alert)
    "fixed" if @alert.is_fixed
  end

  memoize def alert_classifications
    classifications_for_alert_instance(@instance)
  end

  def show_experimental_label?
    experimental_tag_path && show_experimental_query_info_for_tags_and_tool?(
      @alert.rule.tags,
      alert_tool
    )
  end

  def filtered_by_resolution_url
    return unless alert_closed?
    return unless @query.present?

    query_value = alert_resolution_query_value(@alert)

    @alerts_code_scanning_index_path_method&.call(query: @query.toggle_qualifier(name: :resolution, value: query_value))
  end

  def filtered_by_tool_url
    @alerts_code_scanning_index_path_method&.call(query: @query.toggle_qualifier(name: :tool, value: alert_tool))
  end

  def filtered_by_path_url
    @alerts_code_scanning_index_path_method&.call(query: @query.toggle_qualifier(name: :path, value: alert_file_path))
  end

  def show_linked_issues?
    @linked_issues.present?
  end

  def linked_issues_count
    @linked_issues.size
  end
end

# typed: true
# frozen_string_literal: true

class CodeScanning::AlertTableRowComponent < ApplicationComponent
  include CodeScanningHelper
  include ScanningHelper

  attr_reader :repository, :show_checkbox, :show_repository, :show_organization, :repository_result_path, :severity_link, :experimental_tag_path, :show_alert_number, :assignees, :tracking_links, :alert_links

  def initialize(
    repository:,
    alert:,
    instance:,
    show_checkbox:,
    show_repository:,
    show_organization:,
    assignees:,
    repository_result_path:,
    severity_link:,
    query:,
    alerts_code_scanning_index_path_method:,
    experimental_tag_path:,
    show_alert_number:,
    tracking_links: [],
    show_alert_links: false,
    alert_links: []
  )
    @repository = repository
    @alert = alert
    @instance = instance
    @show_checkbox = show_checkbox
    @show_repository = show_repository
    @show_organization = show_organization
    @assignees = assignees
    @repository_result_path = repository_result_path
    @severity_link = severity_link
    @query = query
    @alerts_code_scanning_index_path_method = alerts_code_scanning_index_path_method
    @experimental_tag_path = experimental_tag_path
    @show_alert_number = show_alert_number
    @tracking_links = tracking_links
    @show_alert_links = show_alert_links
    @alert_links = alert_links
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

  def show_assignees?
    @assignees.present?
  end

  def show_tracking_links?
    @tracking_links.present?
  end

  def show_alert_links?
    @show_alert_links && alert_links_count.positive?
  end

  memoize def linked_pull_requests
    @alert_links.filter_map(&:pull_request)
  end

  memoize def linked_branches
    @alert_links.filter_map(&:branch)
  end

  def alert_links_count
    linked_pull_requests.size + linked_branches.size
  end

  def single_linked_pull_request?
    linked_pull_requests.size == 1 && linked_branches.empty?
  end

  def single_linked_branch?
    linked_branches.size == 1 && linked_pull_requests.empty?
  end

  def alert_links_button_icon_and_color
    if linked_branches.empty? && linked_pull_requests.present?
      icon_and_colors = linked_pull_requests.map { |pull_request| linked_pull_request_icon_and_color(pull_request) }.uniq
      return icon_and_colors.first if icon_and_colors.one?
    end

    return ["git-branch", :muted] if linked_pull_requests.empty?

    ["git-pull-request", :muted]
  end

  def linked_pull_request_icon_and_color(pull_request)
    if pull_request.merged?
      ["git-pull-request", :done]
    elsif pull_request.closed?
      ["git-pull-request-closed", :closed]
    elsif pull_request.draft?
      ["git-pull-request-draft", :muted]
    else
      ["git-pull-request", :open]
    end
  end

  def linked_pull_request_description(pull_request)
    if pull_request.merged?
      "##{pull_request.number} merged #{time_ago_in_words(pull_request.merged_at)} ago"
    elsif pull_request.closed?
      "##{pull_request.number} closed #{time_ago_in_words(pull_request.closed_at)} ago"
    else
      "##{pull_request.number} opened #{time_ago_in_words(pull_request.created_at)} ago"
    end
  end

  def linked_branch_path(branch)
    tree_path("", branch.name, repository)
  end

  def tracking_issue_icon_and_color(issue)
    if issue.state == "closed" && (issue.state_reason == "duplicate" || issue.state_reason == "not_planned")
      ["skip", :muted]
    elsif issue.state == "closed"
      ["issue-closed", :done]
    else
      ["issue-opened", :open]
    end
  end

  def tracking_issue_label(issue)
    "#{issue.title}"
  end

  def tracking_issue_description(issue)
    if issue.state == "open"
      "##{issue.number} opened #{time_ago_in_words(issue.created_at)} ago"
    else
      "##{issue.number} closed #{time_ago_in_words(issue.closed_at)} ago"
    end
  end
end

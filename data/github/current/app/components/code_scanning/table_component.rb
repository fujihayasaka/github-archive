# typed: true
# frozen_string_literal: true

class CodeScanning::TableComponent < ApplicationComponent
  include CodeScanningHelper

  attr_reader :open_count, :closed_count, :query, :alerts_code_scanning_index_path_method, :repository, :organization, :business, :ref_names, :user, :fixed_result_numbers, :alert_results, :experimental_tag_path, :alert_number_plus_repository_id_to_assignees, :language_percentages

  def initialize(
    open_count:,
    closed_count:,
    query:,
    alerts_code_scanning_index_path_method:,
    repository: nil,
    organization: nil,
    business: nil,
    ref_names: nil,
    user:,
    fixed_result_numbers:,
    alert_results:,
    experimental_tag_path: nil,
    alert_number_plus_repository_id_to_assignees: {},
    language_percentages: []
  )
    @open_count = open_count
    @closed_count = closed_count
    @query = query
    @alerts_code_scanning_index_path_method = alerts_code_scanning_index_path_method
    @repository = repository
    @organization = organization
    @business = business
    @owner = @repository.owner if @repository.present?
    @ref_names = ref_names
    @user = user
    @fixed_result_numbers = fixed_result_numbers
    @alert_results = alert_results
    @experimental_tag_path = experimental_tag_path
    @alert_number_plus_repository_id_to_assignees = alert_number_plus_repository_id_to_assignees
    @language_percentages = language_percentages
    @tracking_links_by_alert_number_plus_repository_id = resolve_tracking_links
  end

  def open_path
    alerts_code_scanning_index_path_method&.call(query: @query.replace_qualifier(name: :is, value: "open"))
  end

  def closed_path
    alerts_code_scanning_index_path_method&.call(query: @query.replace_qualifier(name: :is, value: "closed"))
  end

  def has_both_state_filters?
    @query.closed? && @query.open?
  end

  def closed_filter_applied?
    @query.closed?
  end

  def open_filter_applied?
    @query.open?
  end

  def severity_link_for_result(result)
    severity_symbol = severity_symbol_for_result(result)

    if severity_symbol
      alerts_code_scanning_index_path_method&.call(query: @query.replace_qualifier(name: :severity, value: severity_symbol.to_s.downcase))
    else
      alerts_code_scanning_index_path_method&.call(query: @query.query_string)
    end
  end

  private

  def show_checkbox_for_row?
    @repository.present? && alerts_writable_by_user?(@repository, user)
  end

  def alert_assignees(result)
    alert_number_plus_repository_id_to_assignees[[result.result.number, result.repository.id]] || []
  end

  def tracking_issues_for_alert(alert_result)
    @tracking_links_by_alert_number_plus_repository_id[[alert_result.result.number, alert_result.repository.id]] || []
  end

  def tracking_links_enabled?
    AlertTrackingLinks.phase_2_enabled?(@repository || @organization || @business)
  end

  # Resolves tracking issue IDs for all alert results and returns a mapping of alert numbers to their tracking links
  def resolve_tracking_links
    return {} unless tracking_links_enabled?

    # Collect all issue IDs from all alert results
    all_issue_ids = []

    @alert_results.each do |alert_result|
      next unless alert_result.repository

      issue_ids = alert_result.result.tracking_links.map(&:issue_id).select { |id| id > 0 }
      all_issue_ids.concat(issue_ids)
    end

    return {} if all_issue_ids.empty?

    # Batch-load all issues
    issues_by_id = Issue.legacy_visible_for(all_issue_ids.uniq, viewer: user).includes(:repository).index_by(&:id)

    # Map alert numbers to their resolved Issue records
    result = {}
    @alert_results.each do |alert_result|
      next unless alert_result.repository

      alert_number = alert_result.result.number

      alert_result.result.tracking_links.each do |link|
        issue = issues_by_id[link.issue_id]
        next unless issue

        tracking_link = {
          tracking_system: link.tracking_system,
          issue:,
          tracking_url: link.tracking_url,
        }
        result[[alert_number, alert_result.repository.id]] ||= []
        result[[alert_number, alert_result.repository.id]] << tracking_link
      end
    end

    result
  end
end

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
      alerts_code_scanning_index_path_method&.call(query: @query.toggle_qualifier(name: :severity, value: severity_symbol.to_s.downcase))
    else
      alerts_code_scanning_index_path_method&.call(query: @query.query_string)
    end
  end

  private

  def show_checkbox_for_row?
    @repository.present? && alerts_writable_by_user?(@repository, user)
  end

  def alert_assignees(result)
    return [] unless @repository&.code_scanning_alert_assignment_enabled? || @organization&.feature_flag_enabled?(:code_scanning_alert_assignment, default: false) || @business&.feature_flag_enabled?(:code_scanning_alert_assignment, default: false)
    alert_number_plus_repository_id_to_assignees[[result.result.number, result.repository.id]] || []
  end
end

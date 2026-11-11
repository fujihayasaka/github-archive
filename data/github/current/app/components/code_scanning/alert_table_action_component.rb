# typed: true
# frozen_string_literal: true

class CodeScanning::AlertTableActionComponent < ApplicationComponent
  include CodeScanningHelper

  attr_reader :query, :close_path, :reopen_path, :fixed_result_numbers, :dismiss_alert_button_label, :require_dismissal_comment, :show_assign_to_copilot_button, :assign_to_copilot_path, :repository

  def initialize(
    query:,
    close_path:,
    reopen_path:,
    fixed_result_numbers:,
    dismiss_alert_button_label:,
    require_dismissal_comment:,
    show_assign_to_copilot_button: false,
    assign_to_copilot_path: nil,
    repository: nil
  )
    @query = query
    @close_path = close_path
    @reopen_path = reopen_path
    @fixed_result_numbers = fixed_result_numbers
    @dismiss_alert_button_label = dismiss_alert_button_label
    @require_dismissal_comment = require_dismissal_comment
    @show_assign_to_copilot_button = show_assign_to_copilot_button
    @assign_to_copilot_path = assign_to_copilot_path
    @repository = repository
  end

  def open_filter_applied?
    !@query.closed?
  end
end

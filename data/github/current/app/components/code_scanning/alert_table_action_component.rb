# typed: true
# frozen_string_literal: true

class CodeScanning::AlertTableActionComponent < ApplicationComponent
  include CodeScanningHelper

  attr_reader :query, :alerts_writable, :close_path, :reopen_path, :fixed_result_numbers, :dismiss_alert_button_label, :require_dismissal_comment

  def initialize(
    query:,
    alerts_writable:,
    close_path:,
    reopen_path:,
    fixed_result_numbers:,
    dismiss_alert_button_label:,
    require_dismissal_comment:
  )
    @query = query
    @alerts_writable = alerts_writable
    @close_path = close_path
    @reopen_path = reopen_path
    @fixed_result_numbers = fixed_result_numbers
    @dismiss_alert_button_label = dismiss_alert_button_label
    @require_dismissal_comment = require_dismissal_comment
  end

  def render?
    !!@alerts_writable
  end

  def open_filter_applied?
    !@query.closed?
  end
end

# typed: true
# frozen_string_literal: true

class CodeScanning::AlertTableActionComponent < ApplicationComponent
  include CodeScanningHelper

  attr_reader :query, :alerts_writable, :close_path, :reopen_path, :fixed_result_numbers

  def initialize(
    query:,
    alerts_writable:,
    close_path:,
    reopen_path:,
    fixed_result_numbers:
  )
    @query = query
    @alerts_writable = alerts_writable
    @close_path = close_path
    @reopen_path = reopen_path
    @fixed_result_numbers = fixed_result_numbers
  end

  def render?
    !!@alerts_writable
  end

  def open_filter_applied?
    !@query.closed?
  end
end

# frozen_string_literal: true

class CheckResult
  attr_reader :title, :summary, :status

  STATUSES = [
    "passed",
    "failed",
    "warning",
  ].freeze

  def initialize(status:, title:, summary:)
    raise ArgumentError unless status.in?(STATUSES)

    @status = status
    @title = title
    @summary = summary
  end

  def passed?
    status == "passed"
  end

  def failed?
    status == "failed"
  end

  def warning?
    status == "warning"
  end
end

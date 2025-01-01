# typed: true
# frozen_string_literal: true

class Stafftools::ComplianceReportListItemComponent < ApplicationComponent
  attr_reader :report

  def initialize(report:)
    @report = report
  end

  private

  def report_octicon
    case report.report_type
    when "download"
      :download
    when "link"
      :link
    when "group"
      :"list-unordered"
    end
  end
end

# typed: true
# frozen_string_literal: true

class Stafftools::SlaReportsController < StafftoolsController
  def index
    render "stafftools/sla_reports/index"
  end
end

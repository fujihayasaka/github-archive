# typed: true
# frozen_string_literal: true

class Stafftools::BundledLicenseAssignments::ListComponent < ApplicationComponent
  PAGINATION_CONTROLLER = "stafftools/bundled_license_assignments"

  def initialize(assignments:, action:, query: nil, search_form_path: nil)
    @assignments = assignments
    @action = action
    @query = query
    @search_form_path = search_form_path
  end

  def table_header
    if @query.present?
      "#{@assignments.count} assignments matching \"#{@query}\""
    else
      "#{@assignments.count} assignments"
    end
  end

  def pagination?
    @assignments.total_pages > 1
  end
end

# typed: true
# frozen_string_literal: true

class Stafftools::BundledLicenseAssignments::ListComponent < ApplicationComponent
  PAGINATION_CONTROLLER = "stafftools/bundled_license_assignments"

  def initialize(assignments:, header:, action:, search_form_path: nil)
    @assignments, @header, @action, @search_form_path = assignments, header, action, search_form_path
  end

  def table_header
    "#{@assignments.count} #{@header}"
  end

  def pagination?
    @assignments.total_pages > 1
  end
end

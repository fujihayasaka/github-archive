# typed: true
# frozen_string_literal: true

class OrganizationMembersExportComponent < ApplicationComponent
  attr_reader :export_path, :mx

  def initialize(export_path:, mx: 0)
    @export_path = export_path
    @mx = mx
  end

  private

  def form_arguments
    {
      name: "export_format",
      method: :post,
      class: "js-organization-members-export-form"
    }
  end
end

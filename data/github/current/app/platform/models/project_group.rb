# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectGroup
  attr_reader :items,
              :view,
              :platform_type_name,
              :page_info,
              :total_count

  delegate :field, :title, :value, :view_group_id, to: :group, allow_nil: true

  def initialize(view:, group: nil, items: nil, page_info: nil, total_count: 0)
    raise Platform::Errors::Internal, "view is required" unless view

    @group = group
    @items = items
    @view = view
    @platform_type_name = "ProjectV2Group"
    @page_info = page_info
    @total_count = total_count
  end

  private

  attr_reader :group
end

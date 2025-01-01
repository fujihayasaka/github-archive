# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectGroupedViewItems
  def self.wrap(items, view:, group: nil, v2: true)
    group = if group
      Platform::Models::ProjectItemFieldGroup.new(group:, view:, v2:)
    end

    view_items = items.map do |item_hash|
      item = item_hash[:item]
      sort_values = item&.sort_values
      Platform::Models::ProjectViewItem.new(item:, sort_values:, v2:)
    end

    new(group:, view_items:, view:, v2:)
  end

  attr_reader :group,
              :view_items,
              :view,
              :platform_type_name

  def initialize(view:, group: nil, view_items: nil, v2: true)
    unless view
      raise Platform::Errors::Internal, "view is required"
    end

    @group = group
    @view_items = view_items
    @view = view
    @platform_type_name = v2 ? "ProjectV2GroupedViewItems" : "ProjectNextGroupedViewItems"
  end
end

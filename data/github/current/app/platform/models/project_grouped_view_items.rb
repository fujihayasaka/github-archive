# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectGroupedViewItems
  def self.wrap(items, view:, group: nil)
    group = if group
      Platform::Models::ProjectItemFieldGroup.new(group:, view:)
    end

    view_items = items.map do |item_hash|
      item = item_hash[:item]
      sort_values = item&.sort_values
      Platform::Models::ProjectViewItem.new(item:, sort_values:)
    end

    new(group:, view_items:, view:)
  end

  attr_reader :group,
              :view_items,
              :view,
              :platform_type_name

  def initialize(view:, group: nil, view_items: nil)
    unless view
      raise Platform::Errors::Internal, "view is required"
    end

    @group = group
    @view_items = view_items
    @view = view
    @platform_type_name = "ProjectV2GroupedViewItems"
  end
end

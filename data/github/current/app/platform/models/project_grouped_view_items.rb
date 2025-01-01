# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectGroupedViewItems
  def self.wrap(items, view:, group: nil, v2: true)
    group = if group
      Platform::Models::ProjectItemFieldGroup.new(group: group, view: view, v2: v2)
    end

    view_items = items.map do |item|
      Platform::Models::ProjectViewItem.new(item: item[:item], v2: v2)
    end

    new(group: group, view_items: view_items, view: view, v2: v2)
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

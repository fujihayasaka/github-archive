# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectViewItem
  attr_reader :item, :sort_values, :platform_type_name

  def initialize(item:, sort_values: [], v2: true)
    @item = item
    @sort_values = sort_values
    @platform_type_name = v2 ? "ProjectV2ViewItem" : "ProjectNextViewItem"
  end
end

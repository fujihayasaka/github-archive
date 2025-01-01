# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectViewItem
  attr_reader :item, :platform_type_name

  def initialize(item:, v2: true)
    @item = item
    @platform_type_name = v2 ? "ProjectV2ViewItem" : "ProjectNextViewItem"
  end
end

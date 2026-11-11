# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :field
  attr_accessor :platform_type_name

  def initialize(item, field)
    @field = field
    @item = item
  end

  def async_memex_project_item
    Promise.resolve(@item)
  end
end

# typed: true
# frozen_string_literal: true

class Site::Header::DynamicContextRegionComponent < ApplicationComponent
  ITEM_ACCESS_TYPE_ICON_MAPPING = {
    default: "",
    public: "",
    internal: "",
    private: "",
  }

  # the total number of items that can be displayed in the context region,
  # (this includes the "..." overflow menu button when visible)
  # if this is set to a value of 3 or higher, it won't require any front-end changes
  MAX_CONTEXT_ITEMS = 5

  attr_reader :context_items, :current_path

  def initialize(context_items: [], current_path: nil)
    @context_items = context_items
    @current_path = current_path
  end

  memoize def responsive_enabled?
    feature_enabled_globally_or_for_user?(feature_name: :responsive_context_region)
  end
end

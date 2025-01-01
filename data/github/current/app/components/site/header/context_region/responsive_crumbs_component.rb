# typed: true
# frozen_string_literal: true

class Site::Header::ContextRegion::ResponsiveCrumbsComponent < Site::Header::ContextRegion::DynamicCrumbsComponent
  attr_reader :visible_crumbs, :overflow_crumbs, :max_context_items

  def initialize(context_items = [], current_path = nil, max_context_items:)
    super(context_items, current_path)
    @visible_crumbs = []
    @overflow_crumbs = []
    @max_context_items = max_context_items

    determine_visible_and_overflow_crumbs
  end

  def determine_visible_and_overflow_crumbs
    if context_crumbs.size <= max_context_items
      @visible_crumbs = context_crumbs
      return
    end

    # we want to force the first and last crumbs to be visible by default, then as many more crumbs that will fit under the max limit, starting from right to left
    # this is to ensure that the last crumb is always visible, even if it is a long name
    # this is to ensure that the first crumb is always visible, even if it is a long name
    @visible_crumbs = context_crumbs.first(1) + context_crumbs.last(max_context_items - 2)
    @overflow_crumbs = context_crumbs[1..-2] - visible_crumbs
  end
end

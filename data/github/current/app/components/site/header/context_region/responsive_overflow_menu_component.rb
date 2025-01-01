# typed: true
# frozen_string_literal: true

class Site::Header::ContextRegion::ResponsiveOverflowMenuComponent < ApplicationComponent
  attr_reader :context_items

  def initialize(context_items = [], include_divider: true)
    @context_items = context_items
    @include_divider = include_divider
  end

  def include_divider?
    @include_divider
  end

  def item_href(item)
    if item.has_path?
      helpers.context_crumb_path(item)
    elsif item.has_href?
      item.href
    else
      nil
    end
  end
end

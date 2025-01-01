# typed: true
# frozen_string_literal: true

require "will_paginate/view_helpers/action_view"

class SponsorsExplorePaginationLinkRenderer < WillPaginateRenderer
  include HydroHelper

  # Copy of the upstream will_paginate page_number implementation with the addition of `data_attributes` when not the current page.
  # `WillPaginateRenderer` will otherwise add `data-total-pages` if this is the current page
  def page_number(page)
    return super(page) if page == current_page
    aria_label = @template.will_paginate_translate(:page_aria_label, page: page.to_i) { "Page #{page}" }
    attrs = { rel: rel_value(page), "aria-label": aria_label }.merge(data_attributes_for(page))
    link(page, page, attrs)
  end

  def previous_or_next_page(page, text, classname, aria_label = nil)
    return super unless page
    link(text, page, data_attributes_for(page).merge(class: classname, "aria-label": aria_label))
  end

  private

  def data_attributes_for(page)
    hydro_click_tracking_attributes("sponsors.explore_pagination_click", current_page: current_page, new_page: page)
      .map { |key, value| ["data-#{key}", value] }
      .to_h
  end
end

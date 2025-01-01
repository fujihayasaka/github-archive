# typed: true
# frozen_string_literal: true

require "will_paginate/view_helpers/action_view"

class CompactPaginationLinkRenderer < WillPaginateRenderer
  def to_html
    return "" if @collection.total_pages <= 1

    items = []
    items << previous_page
    items << compact_page_number(1) if current_page > 1
    items << gap if current_page > 2
    items << compact_page_number(current_page)
    items << gap if current_page < total_pages - 1
    items << compact_page_number(total_pages) if current_page < total_pages
    items << next_page

    # join without extra whitespace; spacing is handled by small margin utility classes
    html_container(items.join(""))
  end

  protected

  def gap
    tag(:span, "…", class: "gap d-inline-block")
  end

  def total_pages
    @collection.total_pages
  end

  def compact_page_number(page)
    aria_label = @template.will_paginate_translate(:page_aria_label, page: page.to_i) { "Page #{page}" }

    if page == current_page
      tag(:em, page, class: "current d-inline-block", "aria-label": aria_label, "aria-current": "page", "data-total-pages": total_pages)
    else
      link(page, page, rel: rel_value(page), "aria-label": aria_label, class: "d-inline-block")
    end
  end
end

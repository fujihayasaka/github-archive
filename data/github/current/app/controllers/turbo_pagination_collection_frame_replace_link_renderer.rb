# typed: true
# frozen_string_literal: true

class TurboPaginationCollectionFrameReplaceLinkRenderer < WillPaginateRenderer
  # Public: Allows Turbo pagination with frame replacement
  # see https://turbo.hotwired.dev/reference/frames#frame-with-overwritten-navigation-targets
  #
  # Examples
  #
  #   <turbo-frame id="paginated-collection-frame">
  #     <% collection.each do |item| %>
  #       <% ... %>
  #     <% end %>
  #
  #     <% if collection.respond_to?(:total_pages) %>
  #       <%= will_paginate(collection, renderer: TurboPaginationCollectionFrameReplaceLinkRenderer) %>
  #     <% end %>
  #   </turbo-frame>
  #
  # Returns a String.
  def link(text, target, attributes = {})
    attributes[:"data-turbo-frame"] = "paginated-collection-frame"
    super
  end
end

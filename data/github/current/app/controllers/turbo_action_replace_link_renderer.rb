# typed: true
# frozen_string_literal: true

class TurboActionReplaceLinkRenderer < WillPaginateRenderer
  # Public: Allows Turbo pagination with history replacement
  # see https://turbo.hotwired.dev/reference/frames#frame-that-promotes-navigations-to-visits.
  #
  # Examples
  #
  #   will_paginate(collection, renderer: TurboActionReplaceLinkRenderer)
  #
  # Returns a String.
  def link(text, target, attributes = {})
    attributes[:"data-turbo-action"] = "replace"
    super
  end
end

# typed: true
# frozen_string_literal: true

require "badge_ruler"

module ZeroUser
  class LinkComponent < ApplicationComponent
    attr_reader :html_class, :label, :href, :text

    def initialize(html_class: nil, label:, href:)
      @html_class = html_class
      @label = label
      @href = href
    end
  end
end

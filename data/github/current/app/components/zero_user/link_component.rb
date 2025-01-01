# typed: true
# frozen_string_literal: true

require "badge_ruler"

module ZeroUser
  class LinkComponent < ApplicationComponent
    attr_reader :html_class, :label, :href, :inline, :text

    def initialize(html_class: nil, label:, href:, inline: false)
      @html_class = html_class
      @label = label
      @href = href
      @inline = inline
    end
  end
end

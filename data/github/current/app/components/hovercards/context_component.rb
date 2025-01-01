# typed: true
# frozen_string_literal: true

module Hovercards
  class ContextComponent < ApplicationComponent
    include ViewComponent::InlineTemplate

    erb_template <<~'ERB'
      <%= render component do %>
        <%= icon %>
        <%= body %>
      <% end %>
    ERB

    renders_one :icon, ->(**kwargs) {
      kwargs[:tag] ||= :div
      kwargs[:mr] ||= 1
      kwargs[:flex_shrink] ||= 0

      Primer::BaseComponent.new(**kwargs)
    }

    renders_one :body, ->(**kwargs) {
      kwargs[:tag] ||= :span
      kwargs[:classes] ||= "lh-condensed overflow-hidden no-wrap"
      kwargs[:style] ||= "text-overflow: ellipsis;"

      Primer::BaseComponent.new(**kwargs)
    }

    def initialize(test_selector: nil, **kwargs)
      @kwargs = kwargs
      @kwargs[:tag] ||= :div
      @kwargs[:display] ||= :flex
      @kwargs[:align_items] ||= :baseline
      @kwargs[:font_size] ||= 6
      @kwargs[:mt] ||= 1
      @kwargs[:color] ||= :muted

      if test_selector
        @kwargs[:data] ||= {}
        @kwargs[:data].merge!(test_selector_hash(test_selector))
      end
    end

    private

    def render?
      body.present? && icon.present?
    end

    def component
      Primer::BaseComponent.new(**@kwargs)
    end
  end
end

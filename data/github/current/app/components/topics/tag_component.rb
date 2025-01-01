# typed: true
# frozen_string_literal: true

module Topics
  class TagComponent < ApplicationComponent
    include ViewComponent::InlineTemplate

    erb_template <<~'ERB'
      <%= render Primer::BaseComponent.new(**@kwargs) do %>
        <%= @name %>
      <% end %>
    ERB

    HOVER_DEFAULT = true
    HOVER_OPTIONS = [HOVER_DEFAULT, false]

    OUTLINE_DEFAULT = false
    OUTLINE_OPTIONS = [OUTLINE_DEFAULT, true]

    def initialize(name:, href:, hover: HOVER_DEFAULT, outline: OUTLINE_DEFAULT, **kwargs)
      @name, @href, @kwargs = name, href, kwargs

      @kwargs[:tag] = :a
      @kwargs[:href] = @href
      @kwargs[:title] ||= "Topic: #{@name}"

      @kwargs[:classes] = class_names(
        @kwargs[:classes],
        "topic-tag",
        "topic-tag-link" => fetch_or_fallback(HOVER_OPTIONS, hover, HOVER_DEFAULT),
        "topic-tag-outline" => fetch_or_fallback(OUTLINE_OPTIONS, outline, OUTLINE_DEFAULT)
      )
    end

    private

    def render?
      @name.present? && @href.present?
    end
  end
end

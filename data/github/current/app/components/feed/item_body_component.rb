# typed: false
# frozen_string_literal: true

module Feed
  class ItemBodyComponent < ApplicationComponent
    renders_one :title, -> (**system_arguments, &block) do
      content = block.call
      return if content.blank?
      render Primer::Beta::Heading.new(
        tag: :h3,
        mt: 2,
        mb: 2,
        classes: "lh-condensed",
        test_selector: "feed-item-card-title",
        **system_arguments
      ).with_content(content)
    end

    renders_one :subheader

    renders_one :preview_image, -> (src:, alt:, **system_arguments) do
      return if src.blank?
      render Primer::Alpha::Image.new(
        src: src,
        alt: alt,
        h: :fit,
        w: :full,
        style: "object-fit: cover;",
        **system_arguments
      )
    end

    renders_one :preview_markdown, -> (**system_arguments, &block) do
      content = block.call
      return if content.blank?

      system_arguments[:aria] = {
        label: "card preview"
      }.merge!(system_arguments[:aria] || {})

      render Primer::BaseComponent.new(
        tag: :section,
        m: 0,
        p: 0,
        classes: "dashboard-break-word comment-body markdown-body #{system_arguments[:classes]}",
        test_selector: "feed-item-card-preview",
        **system_arguments
      ).with_content(content)
    end

    def initialize(**system_arguments)
      @system_arguments = system_arguments
      @system_arguments[:aria] = {
        label: "card content",
      }.merge!(system_arguments[:aria] || {})
    end

    def render?
      !title.blank? || !preview_markdown.blank? || !content.blank?
    end
  end
end

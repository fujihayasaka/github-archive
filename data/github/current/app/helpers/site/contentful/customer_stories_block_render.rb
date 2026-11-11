# typed: true
# frozen_string_literal: true

require "rich_text_renderer"

module Site
  module Contentful
    class CustomerStoriesBlockRender < RichTextRenderer::BaseNodeRenderer

      def render(node)
        entry = node["data"]["target"]

        case entry.content_type.id
        when "testimonial"
          Site::Contentful::CustomerStories::TestimonialComponent.new(entry).render_in(EmptyController.new.view_context)
        end
      end

    end
  end
end

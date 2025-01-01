# typed: true
# frozen_string_literal: true

require "rich_text_renderer"

module Site
  module Contentful
    class SilentNullRenderer < RichTextRenderer::BaseNodeRenderer
      def render(node)
        ""
      end
    end
  end
end

# typed: true
# frozen_string_literal: true

require "rich_text_renderer"

module Site
  module Contentful
    class ReadmeInlineRenderer < RichTextRenderer::BaseNodeRenderer
      include ActionView::Helpers::UrlHelper

      def render(node)
        entry = node["data"]["target"]

        case entry.content_type.id
        when "bodyCodeLink"
          link_to(entry.text, entry.url, class: "code-link")
        else
          content_tag(:p, "INLINE #{entry.content_type.id}", style: "color:red;font-weight:bold")
        end
      end
    end
  end
end

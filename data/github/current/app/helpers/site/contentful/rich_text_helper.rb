# typed: true
# frozen_string_literal: true

require "rich_text_renderer"

module Site
  module Contentful
    module RichTextHelper
      def contentful_rich_text(rich_text)
        renderer = RichTextRenderer::Renderer.new(
          nil => SilentNullRenderer
        )

        html = renderer.render(rich_text)
        GitHub::Goomba::SiteReadmePipeline.to_html(html)
      end

      def contentful_readme_rich_text(rich_text)
        renderer = RichTextRenderer::Renderer.new(
          "embedded-entry-block" => ReadmeBlockRenderer,
          "embedded-entry-inline" => ReadmeInlineRenderer,
          nil => SilentNullRenderer
        )

        html = renderer.render(rich_text)
        GitHub::Goomba::SiteReadmePipeline.to_html(html)
      end

      def contentful_customer_stories_rich_text(rich_text)
        renderer = RichTextRenderer::Renderer.new(
          "embedded-entry-block" => CustomerStoriesBlockRender,
          "embedded-asset-block" => AssetBlockRenderer,
          nil => SilentNullRenderer
        )

        html = renderer.render(rich_text)
        GitHub::Goomba::SiteReadmePipeline.to_html(html)
      end
    end
  end
end

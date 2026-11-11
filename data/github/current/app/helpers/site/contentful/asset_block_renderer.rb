# typed: true
# frozen_string_literal: true

require "rich_text_renderer"

# Deviates from RichTextRenderer::AssetBlockRenderer by using the description for the alt text instead of the title.
# These methods are called in RichTextRenderer and not directly in the monolith so they are included in test/fixtures/unused_helper_methods.txt.
module Site
  module Contentful
    class AssetBlockRenderer < RichTextRenderer::AssetBlockRenderer
      IMAGE_HTML = ->(url, text) { "<img src=\"#{url}\" alt=\"#{text}\" />" }

      protected

      def render_asset(asset, node = nil)
        if asset.file.respond_to?(:content_type) && asset.file.content_type.include?("image")
          return render!(IMAGE_HTML, asset.url, asset.description)
        end

        super
      end

      def render_hash(asset, node = nil)
        if asset.fetch("fields", {}).fetch("file", {}).fetch("contentType", "").include?("image")
          return render!(IMAGE_HTML, asset["fields"]["file"]["url"], asset["fields"]["description"])
        end

        super
      end
    end
  end
end

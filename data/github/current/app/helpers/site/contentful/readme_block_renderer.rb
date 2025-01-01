# typed: true
# frozen_string_literal: true

require "rich_text_renderer"
module Site
  module Contentful
    class ReadmeBlockRenderer < RichTextRenderer::BaseNodeRenderer
      include ActionView::Helpers::AssetTagHelper
      include ActionView::Helpers::TagHelper
      include Site::Contentful::RichTextHelper

      IMAGE_CLASSES = {
        "Fullbleed": "readme-img-fullbleed",
        "Landscape": "img-landscape",
        "Portrait": "img-portrait",
        "Inline": "img-block"
      }.freeze

      IMAGE_SIZES = {
        "Fullbleed": "100vw",
        "Landscape": "(max-width: 1280px) 90vw, 1200px",
        "Portrait": "(max-width: 543px) 90vw, (max-width: 1280px) 46vw, 588px",
        "Inline": "(max-width: 930px) 90vw, 840px"
      }.freeze

      def render(node)
        entry = node["data"]["target"]

        case entry.content_type.id
        when "bodyCodeBlock"
          render_body_code(entry)
        when "bodyExternalVideo"
          render_body_external_video(entry)
        when "bodyImage"
          render_body_image(entry)
        when "bodyList"
          render_body_list(entry)
        when "bodyQuote"
          render_body_quote(entry)
        when "bodyTip"
          render_body_tip(entry)
        else
          content_tag(:p, "BLOCK #{entry.content_type.id}", style: "color:red;font-weight:bold")
        end
      end

      private

      def render_body_image(entry)
        width = entry.image.file.details["image"]["width"]
        height = entry.image.file.details["image"]["height"]

        # Because this class defines a custom render() method
        # we use the ViewComponent's render_in() method
        # and pass in a new view_context. Needed to render.
        Site::ContentfulImageComponent.new(
          src: entry.image.url,
          width: width,
          height: height,
          classes: IMAGE_CLASSES.with_indifferent_access[entry.layout],
          alt: entry.alt_text,
          max_width: 2400,
          sizes: IMAGE_SIZES.with_indifferent_access[entry.layout]
        ).render_in(EmptyController.new.view_context)
      end

      def render_body_list(entry)
        case entry.slug
        when "best-practices", "key-indicators", "overview-statistics"
          content_tag(:h4, entry.name, class: "readme-#{entry.slug}-contentful")
        else
          content_tag(:p, "BLOCK #{entry.content_type.id} #{entry.slug}", style: "color:red;font-weight:bold")
        end
      end

      def render_body_tip(entry)
        rich_text = contentful_rich_text(entry.text)

        content_tag(:div, rich_text, class: "readme-cta")
      end

      def render_body_external_video(entry)
        content_tag(:div, content_tag(:iframe, entry.title, src: entry.url, title: entry.title, frameborder: "0", allow: "autoplay; fullscreen", allowfullscreen: true), class: "video-responsive color-shadow-extra-large color-bg-emphasis mb-6")
      end

      def render_body_quote(entry)
        Site::Readme::Shared::BodyQuoteComponent.new(quote: entry.text).render_in(EmptyController.new.view_context)
      end

      def render_body_code(entry)
        Site::CodeBlockComponent.new(
          file: {
            name: entry.file_name,
            code: <<~EOS
              #{entry.code}
            EOS
          },
          classes: "rounded p-4 mb-3 text-mono f4 color-bg-subtle",
        ).render_in(EmptyController.new.view_context)
      end
    end
  end
end

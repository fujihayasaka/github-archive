# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class BodyComponent < ApplicationComponent
        include SiteHelper
        include Site::ContentfulHelper

        def initialize(
            text_with_media_sections:,
            page_break_image: nil,
            page_break_text: nil,
            by_the_numbers_intro: nil,
            by_the_numbers_sections: nil,
            page_wrap_up_text: nil,
            page_footnote_pre_text: nil,
            page_footnote_post_text: nil,
            page_footer_cta_title: nil,
            page_footer_cta_text: nil,
            about_careers_path: "https://github.careers"
          )

          @text_with_media_sections = text_with_media_sections
          @page_break_image = page_break_image
          @page_break_text = page_break_text
          @by_the_numbers_intro = by_the_numbers_intro
          @by_the_numbers_sections = by_the_numbers_sections
          @page_wrap_up_text = page_wrap_up_text
          @page_footnote_pre_text = page_footnote_pre_text
          @page_footnote_post_text = page_footnote_post_text
          @page_footer_cta_title = page_footer_cta_title
          @page_footer_cta_text = page_footer_cta_text
          @about_careers_path = about_careers_path
        end

        def render?
          @text_with_media_sections.present?
        end
      end
    end
  end
end

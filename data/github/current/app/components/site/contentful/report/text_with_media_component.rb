# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class TextWithMediaComponent < ApplicationComponent
        include SiteHelper
        include Site::ContentfulHelper

        def initialize(id:, heading:, text:, image_components: [], link_components: [], audio_component: nil, audio_transcript_file_name: "", audio_description: "")
          @id = id
          @heading = heading
          @text = text
          @image_components = image_components
          @link_components = link_components
          @audio_component = audio_component
          @audio_transcript_file_name = audio_transcript_file_name
          @audio_description = audio_description
        end

        def render?
          @id.present? && @heading.present? && @text.present?
        end
      end
    end
  end
end

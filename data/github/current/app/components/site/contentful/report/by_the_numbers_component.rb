# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class ByTheNumbersComponent < ApplicationComponent
        include SiteHelper
        include Site::ContentfulHelper

        def initialize(id:, heading:, subheading: "", text:, segmented_content:)
          @id = id
          @heading = heading
          @subheading = subheading
          @text = text
          @segmented_content = segmented_content
        end

        def render?
          @id.present? && @heading.present? && @text.present? && @segmented_content.present?
        end
      end
    end
  end
end

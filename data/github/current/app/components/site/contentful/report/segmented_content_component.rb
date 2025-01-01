# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class SegmentedContentComponent < ApplicationComponent
        def initialize(segments:, is_sub_nav: false, label:)
          @segments = segments
          @is_sub_nav = is_sub_nav
          @label = strip_tags(label)
        end

        def render?
          @segments.present?
        end
      end
    end
  end
end

# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class BarGraphComponent < ApplicationComponent
        def initialize(image:, label: "")
          @image = image
          @label = label
        end

        def render?
          @image.present?
        end
      end
    end
  end
end

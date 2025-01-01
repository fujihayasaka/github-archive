# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class PieGraphComponent < ApplicationComponent
        def initialize(image:, legend:)
          @image = image
          @legend = legend
        end

        def render?
          @image.present? && @legend.present?
        end
      end
    end
  end
end

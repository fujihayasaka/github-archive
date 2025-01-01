# typed: true
# frozen_string_literal: true

module Site
  module Contentful
    module Report
      class PieGraphLabelComponent < ApplicationComponent
        def initialize(label:, percentage:, fill:)
          @label = label
          @percentage = percentage
          @fill = fill
        end

        def render?
          @label.present? && @percentage.present? && @fill.present?
        end
      end
    end
  end
end

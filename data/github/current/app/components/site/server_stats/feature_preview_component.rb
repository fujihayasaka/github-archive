# typed: true
# frozen_string_literal: true

module Site
  module ServerStats
    class FeaturePreviewComponent < ApplicationComponent
      attr_reader :feature_previews_info
      attr_reader :title

      def initialize(title:, feature_previews_info:)
        @feature_previews_info = feature_previews_info
        @title = title
      end

      private

      def render?
        feature_previews_info.present?
      end
    end
  end
end

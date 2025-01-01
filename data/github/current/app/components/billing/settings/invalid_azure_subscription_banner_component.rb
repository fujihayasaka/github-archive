# typed: true
# frozen_string_literal: true

module Billing
  module Settings
    class InvalidAzureSubscriptionBannerComponent < ApplicationComponent
      attr_reader :dismissal_path

      def initialize(is_enabled: false, is_invoiced:, has_dismissed_notice:, dismissal_path:)
        @is_enabled = is_enabled
        @is_invoiced = is_invoiced
        @has_dismissed_notice = has_dismissed_notice
        @dismissal_path = dismissal_path
      end

      def render?
        is_enabled && !is_invoiced && !has_dismissed_notice
      end

      private

      attr_reader :is_enabled, :is_invoiced, :has_dismissed_notice
    end
  end
end

# typed: true
# frozen_string_literal: true

module Stafftools
  module OauthTokens
    class IndexComponent < ApplicationComponent
      def initialize(access:)
        @access = access
      end

      private

      attr_reader :access

      def render?
        access.present?
      end

      def token_expiry_indicator
        if access.expires_at.nil? || access.expires_at > Time.current + 2.weeks
          :accent
        elsif access.expires_at > Time.current
          :attention
        else
          :danger
        end
      end
    end
  end
end

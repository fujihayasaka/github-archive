# typed: true
# frozen_string_literal: true

module Platform::Models
  module Conduit
    class FeedFilter
      attr_reader :name, :is_enabled, :user

      def initialize(name:, is_enabled:, user:)
        @name = name
        @is_enabled = is_enabled
        @user = user
      end

      def filter_group
        Platform::Enums::DashboardFeedFilterGroup.from_filter_name(name)
      end
    end
  end
end

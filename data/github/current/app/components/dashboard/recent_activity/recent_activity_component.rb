# typed: true
# frozen_string_literal: true

module Dashboard
  module RecentActivity
    class RecentActivityComponent < ApplicationComponent
      extend T::Sig

      RECENT_ACTIVITY_ITEM_COUNT = 8

      sig { params(recent_interactions: T::Array[Issue::RecentInteractions], mobile: T::Boolean).void }
      def initialize(recent_interactions:, mobile: false)
        @recent_interactions = recent_interactions
        @mobile = mobile
      end

      private

      sig { returns(T::Array[Issue::RecentInteractions]) }
      attr_reader :recent_interactions

      sig { returns(T::Boolean) }
      attr_reader :mobile

      sig { returns(T::Boolean) }
      def render?
        recent_interactions.any?
      end
    end
  end
end

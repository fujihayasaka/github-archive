# typed: strict
# frozen_string_literal: true

module Copilot
  module CodeReview
    class Features
      sig { params(copilot_user: T.any(Copilot::User, Copilot::Public::User)).void }
      def initialize(copilot_user)
        @copilot_user = copilot_user
      end

      sig { params(copilot_user: T.any(Copilot::User, Copilot::Public::User)).returns(T::Boolean) }
      def self.reply_hint_enabled?(copilot_user)
        new(copilot_user).reply_hint_enabled?
      end

      sig { returns(T::Boolean) }
      def reply_hint_enabled?
        return false unless opted_in_to_preview_features?

        copilot_user.feature_flag_enabled?(:copilot_code_review_reply_hint, default: false)
      end

      private

      sig { returns(T.any(Copilot::User, Copilot::Public::User)) }
      attr_reader :copilot_user

      sig { returns(T::Boolean) }
      def opted_in_to_preview_features? = ::Copilot::Policies::CodeReviewBetaFeatures.available_for?(copilot_user)
    end
  end
end

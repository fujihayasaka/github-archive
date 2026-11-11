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

      # Returns true iff the repository owner has opted in to Copilot Code Review
      # preview features. Uses the per-account `code_review_beta_features_enabled?`
      # helper (Pro/Pro+/free-tier aware) rather than the raw policy check.
      #
      # Dispatches on `repository.owner` (not `in_organization?`) so user-owned
      # private forks of org repos consult the owning user's preview opt-in
      # rather than the inherited parent org.
      sig { params(repository: Repository).returns(T::Boolean) }
      def self.preview_features_enabled_for_repo?(repository)
        owner = repository.owner
        case owner
        when ::Organization
          ::Copilot::Organization.new(owner).code_review_beta_features_enabled?
        when ::User
          ::Copilot::Public::User.new(owner).code_review_beta_features_enabled?
        else
          false
        end
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

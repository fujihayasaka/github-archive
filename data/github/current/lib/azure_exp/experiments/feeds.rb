# typed: true
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module Feeds
      FEEDS_NAMESPACE = "feeds"
      FEEDS_SURFACE = "feed"

      # First two letters of the repo + issue number
      STICKY_ANNOUNCEMENT_EXP_ID = "Fe1444".freeze

      sig { params(user: User).returns(T::Boolean) }
      def sticky_announcements_enabled?(user)
        # Flipper check is used as a kill switch
        return false unless user.feature_enabled?(:multiple_pinned_announcements)

        # Force a user even if they're not officially in the experiment
        return true if user.feature_enabled?(:force_multiple_pinned_announcements)

        assignment = feeds_assignment(user)
        assignment.in_group?(
          group_name: STICKY_ANNOUNCEMENT_EXP_ID,
          expected_value: "true"
        )
      end

      sig { params(user: User).returns(Beta::OverridableExpAssignmentProvider) }
      def feeds_assignment(user)
        Beta::OverridableExpAssignmentProvider.new(
          participant: Beta::Participant.from_user(user),
          namespace: FEEDS_NAMESPACE,
          surface: FEEDS_SURFACE,
          disable_cache: user.feature_enabled?(:disable_azure_exp_cache)
        )
      end

      private

      sig { params(user: User).returns(T::Hash[String, AzureEXP::Beta::ParameterType]) }
      def variants(user)
        participant = AzureEXP::Beta::Participant.from_user(user)
        AzureEXP::Beta::LocalAssignmentService.parameters(participant: participant, namespace: FEEDS_NAMESPACE)
      end
    end

    extend Feeds
  end
end

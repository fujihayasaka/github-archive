# typed: true
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module Feeds
      FEEDS_NAMESPACE = "feeds"
      FEEDS_SURFACE = "feed"

      sig { params(user: User).returns(Beta::OverridableExpAssignmentProvider) }
      def feeds_assignment(user)
        Beta::OverridableExpAssignmentProvider.new(
          participant: Beta::Participant.from_user(user),
          namespace: FEEDS_NAMESPACE,
          surface: FEEDS_SURFACE,
          disable_cache: user.feature_flag_enabled?(:disable_azure_exp_cache, default: false)
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

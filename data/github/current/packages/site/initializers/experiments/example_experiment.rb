# typed: true
# frozen_string_literal: true

# Use this as an example for how to build experiment classes.
module AzureEXP
  module Experiments

    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def self.in_treatment_for_example_experiment?(user)
      # Generally good to check if the user is present and to have a guarding feature flag in place.:
      return false unless user.present?
      return false unless user.feature_flag_enabled?(:example_feature_flag, default: false)

      ExampleExperiment.new(user).treatment_a?
    end

    class ExampleExperiment

      sig { params(user: User).void }
      def initialize(user)
        @user = user
      end

      sig { returns(AzureEXP::Beta::Participant) }
      def participant
        AzureEXP::Beta::Participant.from_user(@user)
      end

      sig { returns(T::Boolean) }
      def treatment_a?
        provider.in_group?(group_name: "example_variable", expected_value: "treatment_a")
      end

      private

      def provider
        AzureEXP::Beta::OverridableExpAssignmentProvider.new(participant: participant, namespace: "webex")
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module CopilotExperiment
      AZURE_EXP_PATH = "exptas16/261c2b97-0c5c-4cda-b7e1-d655cc88bb3a-githubcopilot/api/v1/tas"
      COPILOT_NAMESPACE = "Default"

      COPILOT_AA_TEST = "copilot_api_exp_aa_test"

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def copilot_api_exp_aa_test?(user)
        return false unless user

        provider(user).in_group?(group_name: COPILOT_AA_TEST)
      end

      private

      sig { params(user: User).returns(Beta::OverridableExpAssignmentProvider) }
      def provider(user)
        Beta::OverridableExpAssignmentProvider.new(
          assignment_path: AZURE_EXP_PATH,
          participant: Beta::Participant.from_user(user),
          namespace: COPILOT_NAMESPACE,
          disable_cache: user.feature_flag_enabled?(:disable_azure_exp_cache, default: false)
        )
      end

      extend CopilotExperiment
    end
  end
end

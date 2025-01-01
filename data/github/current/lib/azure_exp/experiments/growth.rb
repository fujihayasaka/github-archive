# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module Growth
      GROWTH_NAMESPACE = "growth"

      MODELS_GET_API_KEY_BUTTON = "models_get_api_key_new_button_text"

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def models_get_api_key_button?(user)
        return false unless user&.feature_enabled?(:github_models_ab_testing)

        provider(user).in_group?(group_name: MODELS_GET_API_KEY_BUTTON)
      end

      private

      sig { params(user: User).returns(Beta::OverridableExpAssignmentProvider) }
      def provider(user)
        Beta::OverridableExpAssignmentProvider.new(
          participant: Beta::Participant.from_user(user),
          namespace: GROWTH_NAMESPACE,
          disable_cache: user.feature_enabled?(:disable_azure_exp_cache)
        )
      end
    end

    extend Growth
  end
end

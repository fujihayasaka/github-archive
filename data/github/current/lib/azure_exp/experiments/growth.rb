# typed: strict
# frozen_string_literal: true

module AzureEXP
  module Experiments
    module Growth
      extend T::Sig

      GROWTH_NAMESPACE = T.let("growth".freeze, String)

      ENTERPRISE_ONBOARDING_ORG_CREATE = T.let("enterprise_onboarding_org_create".freeze, String)

      sig { params(user: T.nilable(User)).returns(T::Boolean) }
      def enterprise_onboarding_org_create?(user)
        return false unless user

        provider(user).in_group?(group_name: ENTERPRISE_ONBOARDING_ORG_CREATE)
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

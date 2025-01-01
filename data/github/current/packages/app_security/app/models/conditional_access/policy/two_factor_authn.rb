# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module TwoFactorAuthn
      # computes applicability of this policy over N targets for conditional access.
      #
      # targets - an Enumerable of targets for conditional access
      #
      # Returns Array[targets] that for which this policy is applicable
      def multiple_two_factor_applicable(targets, target_provider)
        # killswitch for CAP 2FA enforcement, while feature is on hold. This early retyrn avoids N+1 evaluation in two_factor_applicable
        return [] unless GitHub.flipper[:cap_2fa_policy_enabled].enabled?

        targets.filter do |target|
          two_factor_applicable(resource: target, target_provider: target_provider) == :yes
        end

      end

      # computes satisfiability of this policy over N targets for conditional access
      #
      # targets - an Enumerable of targets for conditional access
      #
      # Returns Array[targets] that for which this policy is applicable
      def multiple_two_factor_satisfied(targets, target_provider)
        targets.filter { |target| two_factor_satisfied(resource: target, target_provider: target_provider) == :yes }
      end

      # The 2FA policy is applicable if an organization or business has the corresponding
      # option enabled
      def two_factor_applicable(resource:, target_provider:)
        return :no if T.unsafe(self).anonymous?
        # killswitch for CAP 2FA enforcement, while feature is on hold
        return :no unless GitHub.flipper[:cap_2fa_policy_enabled].enabled?

        # 2FA globally disabled?
        return :no unless GitHub.auth.two_factor_authentication_allowed?(T.unsafe(self).actor)

        target = target_provider.target(resource)
        return :no if target == :no_target_for_conditional_access

        target_is_org = target.is_a?(Organization)
        target_is_business = target.is_a?(Business)

        return :no unless target_is_org || target_is_business

        # enforcement feature flag enabled
        return :no unless target.two_factor_cap_enforcement_enabled?

        # 2FA requirement enabled
        return :no unless target.two_factor_requirement_enabled?

        return :no if target_is_org && !T.unsafe(self).actor.affiliated_with_organization?(target)
        return :no if target_is_business && !T.unsafe(self).actor.is_business_member?(target.id)
        :yes
      end

      # The 2FA policy is satisfied when the user has 2FA enabled
      def two_factor_satisfied(resource:, target_provider:)
        return :yes if T.unsafe(self).actor&.two_factor_authentication_enabled?
        :no
      end
    end
  end
end

# typed: true
# frozen_string_literal: true

module ConditionalAccess
  module Policy
    module EmuPoliciesHelper

      # Is the target for conditional access part of an Enterprise Managed Business?
      #
      # This helper method exists due to the heterogeneous API to determine wether a
      # user/org/biz is EMU. See https://github.com/github/external-identities/issues/790
      def enterprise_managed?(target)
        case target
        when Business
          target.enterprise_managed_user_enabled?
        when  Organization
          # we need to follow the async.sync antipattern here to account for
          # GraphQL requests which need need to access associations asynchronously,
          # while CAP needs to resolve the values immediately to evaluate the policies.
          #
          # This is the only class for which the EMU attribute is not denormalized,
          # and hence requires DB queries.
          target.async_enterprise_managed_user_enabled?.sync
        when User
          target.is_enterprise_managed?
        else
          # We are ensured to have a User/Organization/Business target at this stage.
          # But just for safety, we raise.
          Kernel.raise ArgumentError.new("unsupported target for conditional access: #{target.class.name}")
        end
      end

      def business_for(target)
        return nil if target.nil?

        # account for Integrations and key access
        target = if target.try(:can_have_granular_permissions?)
          target.ability_delegate.async_target.sync
        elsif target.is_a?(Integration)
          target.owner
        elsif target.is_a?(PublicKey)
          target.repository&.business
        else
          target
        end

        case target
        when Business
          target
        when Organization
          target.async_business.sync
        when User
          target.enterprise_managed_business
        else
          # We are ensured to have a User/Organization/Business target at this stage.
          # But just for safety, we raise.
          Kernel.raise ArgumentError.new("unsupported target for conditional access: #{target.class.name}")
        end
      end
    end
  end
end

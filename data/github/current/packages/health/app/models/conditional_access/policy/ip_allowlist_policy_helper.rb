# typed: true
# frozen_string_literal: true

module ConditionalAccess::Policy::IpAllowlistPolicyHelper
  # Get the IP allow list policy owner for a given target.
  #
  # target - Target for conditional access
  #
  # If the target is an EMU (Enterprise Managed User), we want our enforcement
  # messaging to express that the enforcement is occurring due to the policy
  # set at the Business level.
  def policy_owner_for_target(target)
    policy_owner = target

    if target.class == User && target.enterprise_managed_business.present?
      policy_owner = target.enterprise_managed_business
    end

    policy_owner
  end
end

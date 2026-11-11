# typed: true
# frozen_string_literal: true

# This job iterates through the organizations in an enterprise and makes sure the organization policies are at least as restrictive as the enterprise level policy.
# If not it clears the organization policy, which will cause the organization to use the enterprise level policy.
# We do this in a background job in case the enterprise has thousands of organizations, so we don't timeout in a controller action.
class EnsureValidForkingPolicyJob < ApplicationJob
  queue_as :ensure_valid_forking_policy
  retry_on_dirty_exit
  retry_on Faraday::TimeoutError
  use_primaries ApplicationRecord::Configurations

  def perform(business_id: nil, actor_id: nil)
    actor = User.find_by(id: actor_id) if actor_id.present?
    business = Business.find_by(id: business_id) if business_id.present?
    return unless business

    policy = business.get_private_repository_forking_policy
    business.ensure_enterprise_organizations_have_valid_policy_after_update(policy, actor)
  end
end

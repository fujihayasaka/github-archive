# typed: strict
# frozen_string_literal: true

class RemoveUnaffiliatedMemberFromBusinessJob < ApplicationJob

  queue_as :business_membership_cleanup
  retry_on_dirty_exit

  resolve_tenant_context do |business, _user|
    business
  end

  # Public - Job to remove a user from a business if they are an exclusive unaffiliated member.
  #
  # business - The Business to remove the user from
  # user     - The User to potentially remove
  # reason   - The reason for removal (default: "removing unaffiliated user")
  #
  # Returns nothing
  sig { params(business: Business, user: User, reason: String).void }
  def perform(business, user, reason: "removing unaffiliated user")
    return if business.enterprise_managed_user_enabled?
    return unless business.exclusive_unaffiliated_member?(user)

    BusinessOrchestration.remove_members(
      business: business,
      user_ids: [user.id],
      actor: nil,
      reason: reason,
      send_notification: true
    ).execute
  end
end

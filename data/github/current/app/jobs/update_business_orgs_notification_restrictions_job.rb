# typed: true
# frozen_string_literal: true

class UpdateBusinessOrgsNotificationRestrictionsJob < ApplicationJob
  queue_as :update_org_notification_restrictions

  retry_on_dirty_exit

  def perform(business_id, actor_id, verifiable_domain_id, notifications_restricted:)
    business = Business.find(business_id)
    actor = User.find(actor_id)
    with_write do
      business.update_dependent_notification_restriction_policies!(
        verifiable_domain_id,
        actor: actor,
        notifications_restricted: notifications_restricted
      )
    end
  end
end

# typed: true
# frozen_string_literal: true

class DeactivateExpiredSponsorshipsJob < ApplicationJob
  queue_as :sponsorships_maintenance

  retry_on_dirty_exit

  def perform
    sponsorships_to_deactivate = Sponsorship.expired.includes(:tier, :subscription_item).where(active: true)
    sponsorships_to_deactivate.each do |sponsorship|
      force = sponsorship.sponsors_invoiced?
      Sponsorship.throttle_writes_with_retry do
        Billing::SubscriptionItem.throttle_writes_with_retry do
          sponsorship.cancel(actor: sponsorship.sponsor, reason: :EXPIRED_SPONSORSHIP, force: force)
        end
      end
    end
  end
end

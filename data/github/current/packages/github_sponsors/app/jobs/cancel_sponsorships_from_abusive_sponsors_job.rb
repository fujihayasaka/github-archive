# typed: true
# frozen_string_literal: true

class CancelSponsorshipsFromAbusiveSponsorsJob < ApplicationJob
  queue_as :sponsorships_maintenance

  GRACE_PERIOD_IN_DAYS = 7
  BATCH_SIZE = 100
  retry_on_dirty_exit

  def perform
    return unless GitHub.spamminess_check_enabled?

    total_failures = 0
    total_sponsors = 0

    all_sponsor_ids = Sponsorship.active.select(:sponsor_id).distinct.pluck(:sponsor_id)
    all_sponsor_ids.each_slice(BATCH_SIZE) do |sponsor_ids|
      scoped = User.where(id: sponsor_ids)
      spammy_ids = scoped.spammy.pluck(:id)
      suspended_ids = scoped.suspended.pluck(:id)
      next if spammy_ids.empty? && suspended_ids.empty?

      # To keep from inconveniencing our sponsors who get incorrectly suspended or marked spammy, only cancel
      # sponsorships from sponsors who have been suspended or marked as spammy for at least a week:
      ids_of_sponsors_marked_spammy_for_long_enough = User.user_ids_marked_before(
        :spam,
        spammy_ids,
        cutoff_time: GRACE_PERIOD_IN_DAYS.days.ago.beginning_of_day
      ).to_set
      ids_of_sponsors_suspended_for_long_enough = User.user_ids_marked_before(
        :suspension,
        suspended_ids,
        cutoff_time: GRACE_PERIOD_IN_DAYS.days.ago.beginning_of_day
      ).to_set
      next if ids_of_sponsors_marked_spammy_for_long_enough.empty? && ids_of_sponsors_suspended_for_long_enough.empty?

      ids_of_abusive_sponsors_for_long_enough = ids_of_sponsors_marked_spammy_for_long_enough +
        ids_of_sponsors_suspended_for_long_enough

      sponsorships_to_cancel = Sponsorship.active
        .from_sponsor(ids_of_abusive_sponsors_for_long_enough)
        .includes(:tier, :invoiced_sponsorship_transfer, :subscription_item)

      sponsorships_to_cancel.each do |sponsorship|
        result = Sponsorship.throttle_writes_with_retry do
          Billing::SubscriptionItem.throttle_writes_with_retry do
            sponsorship.cancel(actor: nil, reason: :SPAMMY_SPONSOR, force: true)
          end
        end
        total_failures += 1 unless result.success
      end

      total_sponsors += sponsorships_to_cancel.map(&:sponsor_id).uniq.size
    end

    if total_failures > 0
      sponsorship_units = "sponsorship".pluralize(total_failures)
      sponsor_units = "sponsor".pluralize(total_sponsors)
      raise "Failed to cancel #{total_failures} #{sponsorship_units} from #{total_sponsors} spammy or " \
        "suspended #{sponsor_units}"
    end
  end
end

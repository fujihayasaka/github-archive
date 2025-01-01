# typed: true
# frozen_string_literal: true

module Billing
  class CheckUnsuccessfulSubscriptionSynchronizationsJob < BillingJob
    FAILED_BUT_RETRYING_CUTOFF = 12.hours
    FAILURE_CUTOFF = 15.minutes

    queue_as :billing
    schedule interval: 5.minutes, condition: -> { GitHub.billing_enabled? }

    exempt_from_tenant_context_requirement

    # Public: Report metrics on the number of failed subscription synchronizations
    #
    # Returns nothing
    def perform
      # If the sync status is missing a target and Zuora subscription it's likely because the user has
      # has been deleted and we no longer need to try to force the synchronization to succeed.
      bad_syncs = Billing::SubscriptionSyncStatus.unsuccessful.not_under_investigation.ignoring_recent
      with_write { bad_syncs.find_each { |sync| sync.destroy if missing_target_and_zuora_subscription?(sync) } }

      # Manually fail synchronizations that have been in the failed_but_retrying state for over 12 hours.
      # This can happen if the synchronization is triggered from a location where retrys are not configured
      # or if the number of retries is different from what is expected.
      retrying_syncs = Billing::SubscriptionSyncStatus.failed_but_retrying.where("updated_at < :cutoff", cutoff: FAILED_BUT_RETRYING_CUTOFF.ago)
      with_write { retrying_syncs.each { |sync| sync.fail! } }

      # Report failed synchronizations that happened at least 15 minutes ago. New synchronizations may be triggered
      # after a failure if the user is making account changes so we don't want to report failures until we know that
      # there won't be any more retries (automatically or manually).
      failed_syncs = Billing::SubscriptionSyncStatus.failure.where("updated_at < :cutoff", cutoff: FAILURE_CUTOFF.ago)
      GitHub.dogstats.gauge("billing.subscription_sync_status.failure", failed_syncs.count)
    end

    # Internal: Check if the synchronization is missing a target and Zuora subscription
    # This can happen if the user is deleted and the subscription is removed
    #
    # Playbook: https://github.com/github/gitcoin/blob/main/docs/playbook/alerts/unsuccessful_subscription_synchronizations.md#syncs-without-a-target-andor-zuora-account
    #
    # Returns true or false
    def missing_target_and_zuora_subscription?(sync)
      sync.target.nil? && sync&.plan_subscription&.zuora_subscription_number.nil?
    end
  end
end

# typed: true
# frozen_string_literal: true

class SyncSponsorsStripeAccountsJob < ApplicationJob
  queue_as :sponsors_stripe_sync
  retry_on_dirty_exit

  def perform
    accounts_to_sync = Billing::StripeConnect::Account.without_email
    accounts_to_sync.find_each do |stripe_account|
      SyncSponsorsStripeAccountJob.perform_later(stripe_account)
    end
  end
end

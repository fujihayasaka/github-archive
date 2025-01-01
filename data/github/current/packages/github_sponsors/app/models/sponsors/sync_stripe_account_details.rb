# typed: strict
# frozen_string_literal: true

module Sponsors
  class SyncStripeAccountDetails
    # Public: Sync the latest Stripe account details.
    #
    # Will call Stripe's API to retrieve details unless Stripe::Account passed as account_details by the caller.
    #
    # account - Billing::StripeConnect::Account record to update
    # account_details - Stripe::Account object from Stripe containing account details (optional)
    #
    # Returns the updated Billing::StripeConnect::Account. Returns nil if no SponsorsListing exists for the
    # Stripe Connect account. Raises ActiveRecord::RecordInvalid, Stripe::PermissionError, and
    # Billing::StripeConnect::Account::SyncError.
    sig do
      params(
        account: Billing::StripeConnect::Account,
        account_details: T.nilable(Stripe::Account)
      ).returns(T.nilable(Billing::StripeConnect::Account))
    end
    def self.call(account, account_details: nil)
      new(account, account_details).call
    end

    sig { params(account: Billing::StripeConnect::Account, account_details: T.nilable(Stripe::Account)).void }
    def initialize(account, account_details)
      @account = account
      @account_details = account_details
    end

    sig { returns T.nilable(Billing::StripeConnect::Account) }
    def call
      return unless sponsors_listing
      sponsors_listing = T.must(self.sponsors_listing)

      Failbot.push(
        sponsors_listing_id: sponsors_listing.id,
        stripe_verification_status: account.verification_status,
        user_id: sponsors_listing.sponsorable_id,
      )

      update_account!

      GitHub.dogstats.increment("stripe.account_sync", tags: account.datadog_tags)

      try_publish_listing

      account
    end

    private

    sig { returns Billing::StripeConnect::Account }
    attr_reader :account

    sig { returns T.nilable(SponsorsListing) }
    def sponsors_listing
      account.sponsors_listing
    end

    # Private: Raises ActiveRecord::RecordInvalid and Stripe::PermissionError.
    sig { returns T.nilable(Billing::StripeConnect::Account) }
    def update_account!
      @account_details ||= fetch_stripe_account
      account.update_from_stripe!(@account_details.to_hash) if @account_details
      account.reload
    rescue ActiveRecord::RecordInvalid,
        Billing::StripeConnect::Account::SyncError,
        Stripe::APIConnectionError,
        Stripe::StripeError
      increment_account_sync_error_count
      raise
    end

    sig { returns T.nilable(Stripe::Account) }
    def fetch_stripe_account
      Stripe::Account.retrieve(account.stripe_account_id)
    rescue Stripe::PermissionError # account no longer exists on Stripe
      if account.persisted?
        account.soft_delete
        nil
      else
        increment_account_sync_error_count
        raise
      end
    end

    sig { void }
    def try_publish_listing
      return unless sponsors_listing
      listing = T.must(sponsors_listing)

      return unless listing.draft? && listing.sponsorable.present?

      sponsorable = T.must(listing.sponsorable)

      return unless listing.can_publish?
      T.unsafe(listing).publish!(automated: true)
    end

    sig { void }
    def increment_account_sync_error_count
      GitHub.dogstats.increment("stripe.account_sync_error", tags: account.datadog_tags)
    end
  end
end

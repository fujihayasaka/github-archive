# typed: strict
# frozen_string_literal: true

# A Plain Old Ruby Object (PORO) used for updating a Stripe Connect account.
module Sponsors
  class ConfigureStripeAccount
    class UpdatePayoutsFailedError < StandardError; end

    # account - The Billing::StripeConnect::Account to update the configuration for.
    # freeze_payouts - A Boolean indicating if payouts should be frozen.
    # actor - (optional) The User configuring payouts for this account.
    # reason - (optional) The reason payouts are being enabled/disabled.
    sig do
      params(
        account: Billing::StripeConnect::Account,
        freeze_payouts: T::Boolean,
        actor: T.nilable(User),
        reason: T.nilable(String)
      ).returns(Billing::StripeConnect::Account)
    end
    def self.call(account:, freeze_payouts: false, actor: nil, reason: nil)
      new(account: account, freeze_payouts: freeze_payouts, actor: actor, reason: reason).call
    end

    sig do
      params(
        account: Billing::StripeConnect::Account,
        freeze_payouts: T::Boolean,
        actor: T.nilable(User),
        reason: T.nilable(String)
      ).void
    end
    def initialize(account:, freeze_payouts: false, actor: nil, reason: nil)
      @account = account
      @freeze_payouts = freeze_payouts
      @actor = actor
      @reason = reason
    end

    # Public: Updates the configuration for a Stripe Connect account.
    #
    # Returns the Billing::StripeConnect::Account that was updated.
    # Raises Stripe::APIConnectionError if connecting to the Stripe API fails.
    # Raises Stripe::StripeError if updating the Stripe account fails.
    sig { returns Billing::StripeConnect::Account }
    def call
      response = Stripe::Account.update(account.stripe_account_id, {
        settings: {
          payouts: {
            schedule: payout_schedule,
          },
        },
      })

      account.update_from_stripe!(response.as_json)

      if freeze_payouts && !account.automated_payouts_disabled?
        raise UpdatePayoutsFailedError
      end

      if !freeze_payouts && account.automated_payouts_disabled?
        raise UpdatePayoutsFailedError
      end

      instrument_update

      account
    end

    private

    sig { returns Billing::StripeConnect::Account }
    attr_reader :account

    sig { returns T::Boolean }
    attr_reader :freeze_payouts

    sig { returns T.nilable(User) }
    attr_reader :actor

    sig { returns T.nilable(String) }
    attr_reader :reason

    # Private: The payout schedule to use for this account.
    sig { returns T::Hash[Symbol, T.untyped] }
    def payout_schedule
      if freeze_payouts
        { interval: "manual" }
      else
        { interval: "monthly", monthly_anchor: 22 }
      end
    end

    sig { void }
    def instrument_update
      sponsors_listing = account.sponsors_listing
      return unless sponsors_listing
      if freeze_payouts
        sponsors_listing.instrument_auto_payouts_disabled(actor: actor, reason: reason)
      else
        sponsors_listing.instrument_auto_payouts_enabled(actor: actor, reason: reason)
      end
    end
  end
end

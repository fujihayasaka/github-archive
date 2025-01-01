# typed: true
# frozen_string_literal: true

module Sponsors
  class EmitEarlyFraudWarning
    # Public: Emit a Sponsors-relevant early fraud warning Hydro event if chargeback is related
    # to sponsorships
    #
    # early_fraud_warning_event - General early fraud warning event
    #
    # Returns a Boolean indicating whether any events were emitted.
    def self.call(early_fraud_warning_event)
      new(early_fraud_warning_event).call
    end

    def initialize(early_fraud_warning_event)
      @early_fraud_warning_event = early_fraud_warning_event
    end

    def call
      stripe_charge_id = @early_fraud_warning_event[:stripe_charge_id]

      payments = Billing::PayoutsLedgerEntry
        .includes(:sponsors_listing, :sponsorable, :sponsors_listing_stafftools_metadata, :stripe_connect_account)
        .payments_for_charge_id(@early_fraud_warning_event[:stripe_charge_id])

      return false unless payments.present?

      payments.each do |payment|
        # Emits a Hydro event
        payment.instrument_early_fraud_warning(@early_fraud_warning_event)
      end

      true
    end
  end
end

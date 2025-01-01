# typed: strict
# frozen_string_literal: true

module Billing::StripeConnect::Account::HydroDependency
  extend T::Helpers

  requires_ancestor { Billing::StripeConnect::Account }

  extend ActiveSupport::Concern

  # Valid values for the VerificationStatus enum in
  # lib/hydro/schemas/github/sponsors/v1/entities/stripe_connect_account_pb.rb:
  HYDRO_UNKNOWN_VERIFICATION_STATUS = "UNKNOWN"
  HYDRO_VERIFICATION_STATUSES = T.let([HYDRO_UNKNOWN_VERIFICATION_STATUS, "UNVERIFIED_REQUIREMENTS_PAST_DUE",
    "UNVERIFIED_REQUIREMENTS_CURRENTLY_DUE", "UNVERIFIED_DETAILS_NOT_SUBMITTED", "UNVERIFIED_NO_TRANSFERS_CAPABILITY",
    "UNVERIFIED_NO_TAX_REPORTING_CAPABILITY", "UNVERIFIED_NO_CARD_PAYMENTS_CAPABILITY", "UNVERIFIED",
    "VERIFIED"].freeze, T::Array[String])

  HYDRO_UNKNOWN_PAYOUT_INTERVAL = "UNKNOWN_PAYOUT_INTERVAL"
  HYDRO_PAYOUT_INTERVALS = T.let([HYDRO_UNKNOWN_PAYOUT_INTERVAL, "MANUAL", "DAILY", "WEEKLY", "MONTHLY"].freeze, T::Array[String])

  # Public: Get the account's verification status in a value suitable for use in a `VerificationStatus` field in
  # a Hydro schema.
  sig { returns(Symbol) }
  def hydro_verification_status
    normalized_verification_status = verification_status.upcase
    str_status = if HYDRO_VERIFICATION_STATUSES.include?(normalized_verification_status)
      normalized_verification_status
    else
      HYDRO_UNKNOWN_VERIFICATION_STATUS
    end
    str_status.to_sym
  end

  # Public: Get the account's interval for when payouts are made, in a format suitable for a `PayoutInterval` field
  # in a Hydro schema.
  sig { returns(Symbol) }
  def hydro_payout_interval
    normalized_payout_interval = payout_interval&.upcase.to_s
    str_interval = if HYDRO_PAYOUT_INTERVALS.include?(normalized_payout_interval)
      normalized_payout_interval
    else
      HYDRO_UNKNOWN_PAYOUT_INTERVAL
    end
    str_interval.to_sym
  end
end

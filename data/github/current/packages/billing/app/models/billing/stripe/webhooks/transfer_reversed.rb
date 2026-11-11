# typed: true
# frozen_string_literal: true

class Billing::Stripe::Webhooks::TransferReversed
  include GitHub::Memoizer

  TransferReversedError = Class.new(StandardError)
  InvalidDestinationError = Class.new(TransferReversedError)
  InvalidTransferError = Class.new(TransferReversedError)

  INTER_ACCOUNT_TRANSFER_KEY = ::Billing::Stripe::TransferReversal::INTER_ACCOUNT_TRANSFER_KEY

  attr_reader :transfer

  # Public: Handle the transfer reversed webhook payload
  #
  # webhook - The Billing::StripeWebhook to process
  #
  # Returns nothing
  def self.perform(webhook)
    new(webhook).perform
  end

  # Public: Initializes a new TransferReversed webhook handler
  #
  # webhook - The Billing::StripeWebhook to process
  def initialize(webhook)
    @webhook = webhook
    @event = webhook.stripe_event
    @transfer = @event.data.object
  end

  # Public: Handle the transfer created webhook payload
  #
  # Returns nothing
  def perform
    reversals.each do |reversal|
      next if already_processed?(reversal)
      record_reversal(reversal)
      create_transfer(reversal) if inter_account_transfer?(reversal)
    end
  end

  private

  def record_reversal(reversal)
    billing_transaction_id = billing_transaction_ids_by_reversal_id[reversal.id]
    transaction = ::Billing::PayoutsLedgerTransaction.new(stripe_connect_account)

    ref_ids = get_reference_ids_for_transfer_reversal(transfer, reversal)
    transaction.add_entry(
      transaction_type: :transfer_reversal,
      amount_in_subunits: (-1 * reversal.amount),
      currency_code: reversal.currency.upcase,
      primary_reference_id: reversal.id,
      sponsors_listing_id: sponsorship_recipient_listing_id,
      billing_transaction_id: billing_transaction_id,
      reversed_transfer_stripe_id: ref_ids[:reversed_transfer_stripe_id],
      stripe_refund_id: ref_ids[:stripe_refund_id],
      zuora_refund_id: ref_ids[:zuora_refund_id],
      refunded_transaction_stripe_id: ref_ids[:refunded_transaction_stripe_id],
      refunded_transaction_zuora_id: ref_ids[:refunded_transaction_zuora_id],
      invoiced_sponsorship_transfer_reversal_id: ref_ids[:invoiced_sponsorship_transfer_reversal_id]
    )

    if refunded?(reversal)
      stripe_refund_id = reversal.metadata["stripe_refund_id"]
      refunded_transaction_stripe_id = transfer.metadata["stripe_charge_id"]
      refunded_transaction_paypal_id = transfer.metadata["paypal_id"]
      refunded_transaction_credit_balance_adjustment_number =
        transfer.metadata["credit_balance_adjustment_number"]
      refunded_transaction_zuora_id = transfer.transfer_group

      transaction.add_entry(
        transaction_type: :refund,
        amount_in_subunits: payment_refund_amount(reversal),
        currency_code: reversal.currency.upcase,
        primary_reference_id: reversal.metadata["zuora_refund_id"],
        sponsors_listing_id: sponsorship_recipient_listing_id,
        billing_transaction_id: billing_transaction_id,
        stripe_refund_id: stripe_refund_id,
        refunded_transaction_stripe_id: refunded_transaction_stripe_id,
        refunded_transaction_paypal_id: refunded_transaction_paypal_id,
        refunded_transaction_credit_balance_adjustment_number: refunded_transaction_credit_balance_adjustment_number,
        refunded_transaction_zuora_id: refunded_transaction_zuora_id,
      )
    end

    if inter_account_transfer?(reversal)
      transaction.add_entry(
        transaction_type: :inter_account_transfer,
        amount_in_subunits: reversal.amount,
        currency_code: reversal.currency.upcase,
        sponsors_listing_id: sponsorship_recipient_listing_id,
        primary_reference_id: "#{reversal.id}:#{reversal.metadata[INTER_ACCOUNT_TRANSFER_KEY]}",
        billing_transaction_id: billing_transaction_id,
      )
    end

    if invoice_credited?(reversal)
      refunded_transaction_zuora_id = transfer.transfer_group

      transaction.add_entry(
        transaction_type: :invoice_credit,
        amount_in_subunits: reversal.metadata["payment_amount_reversed"].to_i,
        currency_code: reversal.currency.upcase,
        sponsors_listing_id: sponsorship_recipient_listing_id,
        primary_reference_id: invoiced_sponsorship_transfer_reversal_id(reversal),
        billing_transaction_id: billing_transaction_id,
        refunded_transaction_zuora_id: refunded_transaction_zuora_id,
      )
    end

    if match_reversed?(reversal)
      transaction.add_entry(
        transaction_type: :github_match_reversal,
        amount_in_subunits: reversal.metadata["match_amount_reversed"].to_i,
        currency_code: reversal.currency.upcase,
        primary_reference_id: reversal.metadata["zuora_refund_id"] || reversal.id,
        billing_transaction_id: billing_transaction_id,
        sponsors_listing_id: sponsorship_recipient_listing_id,
      )
    end

    transaction.save!

    instrument_transfer_reversal(reversal)
    clear_match_limit_reached_at_if_under_match_limit!(reversal)
  end

  def instrument_transfer_reversal(reversal)
    stripe_refund_id = reversal.metadata["stripe_refund_id"]
    user = Billing::BillingTransaction.find_by(transaction_id: stripe_refund_id)&.live_user
    return unless user.present?

    sponsorship = Sponsorship.find_by(sponsor: user, sponsorable: sponsors_listing.sponsorable)

    if sponsorship.present?
      GlobalInstrumenter.instrument("sponsors.sponsor_transfer_reversal",
        sponsorship: sponsorship,
        listing: sponsors_listing,
        tier: sponsorship.tier,
        total_amount_in_subunits: reversal.amount.to_i,
        payment_amount_in_subunits: reversal.metadata["payment_amount_reversed"].to_i,
        match_amount_in_subunits: reversal.metadata["match_amount_reversed"].to_i,
        currency_code: reversal.currency.upcase,
        listing_stafftools_metadata: sponsors_listing.stafftools_metadata,
      )
    end
  end

  def reversals
    transfer.reversals.data
  end

  memoize def billing_transaction_ids_by_reversal_id
    Billing::BillingTransaction
      .for_zuora_transaction_id(reversals.map(&:id))
      .order(id: :desc)
      .pluck(:platform_transaction_id, :id)
      .to_h
  end

  memoize def stripe_connect_account
    Billing::StripeConnect::Account.including_deleted
      .find_by!(stripe_account_id: transfer.destination)
  end

  def get_reference_ids_for_transfer_reversal(transfer, reversal)
    if refunded?(reversal)
      {
        reversed_transfer_stripe_id: transfer.id,
        stripe_refund_id: reversal.metadata["stripe_refund_id"],
        zuora_refund_id: reversal.metadata["zuora_refund_id"],
        refunded_transaction_stripe_id: transfer.metadata["stripe_charge_id"],
        refunded_transaction_zuora_id: transfer.transfer_group,
      }
    elsif invoice_credited?(reversal)
      {
        reversed_transfer_stripe_id: transfer.id,
        refunded_transaction_zuora_id: transfer.transfer_group,
        invoiced_sponsorship_transfer_reversal_id: invoiced_sponsorship_transfer_reversal_id(reversal),
      }
    else
      {
        reversed_transfer_stripe_id: transfer.id,
        stripe_refund_id: reversal.metadata["stripe_refund_id"],
        zuora_refund_id: reversal.metadata["zuora_refund_id"],
      }
    end
  end

  def refunded?(reversal)
    return false if invoice_credited?(reversal)
    return false if inter_account_transfer?(reversal)
    payment_refund_amount(reversal).positive?
  end

  def match_reversed?(reversal)
    return false if inter_account_transfer?(reversal)
    reversal.metadata["match_amount_reversed"].to_i.positive?
  end

  def invoice_credited?(reversal)
    invoiced_sponsorship_transfer_reversal_id(reversal).present?
  end

  def inter_account_transfer?(reversal)
    destination_account_id = reversal.metadata[INTER_ACCOUNT_TRANSFER_KEY]
    return false unless destination_account_id.present?

    if reversal.amount != transfer.amount
      raise InvalidTransferError.new("Inter-account transfers require full transfer amount.")
    end

    destination_stripe_connect_account = Billing::StripeConnect::Account.find_by!(
      stripe_account_id: destination_account_id
    )
    source_listing_id = stripe_connect_account.sponsors_listing_id
    destination_listing_id = destination_stripe_connect_account.sponsors_listing_id

    if source_listing_id != destination_listing_id
      raise InvalidDestinationError.new("Source listing does not match destination listing.")
    end

    true
  end

  def invoiced_sponsorship_transfer_reversal_id(reversal)
    id_from_metadata = reversal.metadata["invoiced_sponsorship_transfer_reversal_id"].presence
    return unless id_from_metadata
    id_from_metadata.to_i
  end

  # Private: Clears the `match_limit_reached_at` timestamp for the Sponsors listing receiving
  # the sponsorship if we reversed matching funds and put the listing back under the
  # match limit.
  #
  # reversal - A Stripe::StripeObject that is a transfer reversal.
  #
  # Returns a Boolean indicating if the `match_limit_reached_at` column was cleared.
  def clear_match_limit_reached_at_if_under_match_limit!(reversal)
    return false unless match_reversed?(reversal)
    return false if sponsors_listing.match_limit_reached_at.blank?

    sponsors_listing.reset_total_match_in_cents!
    return false if sponsors_listing.reached_match_limit?

    sponsors_listing.update!(match_limit_reached_at: nil)
  end

  # Private: The Sponsors listing ID for the maintainer who is being sponsored. Note this
  # is not necessarily the same listing as what's associated with the Stripe
  # account. The Stripe account could be tied to a fiscal host's listing while
  # the sponsorship was for a maintainer who uses that fiscal host.
  #
  # Returns a SponsorsListing ID or nil.
  memoize def sponsorship_recipient_listing_id
    transfer.metadata[:sponsors_listing_id]
  end

  memoize def sponsors_listing
    if sponsorship_recipient_listing_id
      SponsorsListing.find(sponsorship_recipient_listing_id)
    else
      # If no listing was set in the Stripe metadata for the transfer, fall back to
      # whatever listing the Stripe account is associated with:
      stripe_connect_account.sponsors_listing
    end
  end

  # Private: Is it possible for us to handle the missing refund metadata?
  #
  # We only need the metadata to understand the refund in the case matching was involved, since
  # in that case we want to disambiguate refunded payment vs. refunded matching.
  #
  # Returns a Boolean.
  def can_handle_missing_reversal_metadata?
    transfer.metadata["match_amount"].to_i.zero?
  end

  # Private: Get the refund amount for this reversal
  #
  # Returns an Integer
  def payment_refund_amount(reversal)
    if can_handle_missing_reversal_metadata?
      reversal.amount
    else
      reversal.metadata["payment_amount_reversed"].to_i
    end
  end

  sig { returns T::Set[String] }
  memoize def already_processed_reversal_ids
    reversal_ids = reversals.filter_map(&:id)
    transfer_reversal_ledger_entries =
    transfer_reversal_ledger_entry_reference_ids = stripe_connect_account
      .ledger_entries
      .transfer_reversal
      .where(primary_reference_id: reversal_ids)
      .pluck(:primary_reference_id)
      .to_set
  end

  sig { params(reversal: T.untyped).returns(T::Boolean) }
  def already_processed?(reversal)
    already_processed_reversal_ids.include?(reversal.id)
  end

  def create_transfer(reversal)
    metadata = transfer.metadata.to_h
    reversal_metadata = reversal.metadata.to_h
    metadata.merge!({
      payment_amount: reversal_metadata[:payment_amount_reversed],
      match_amount: reversal_metadata[:match_amount_reversed],
      transferred_from_account: transfer.destination,
      transferred_from_reversal: reversal.id,
    })
    ::Stripe::Transfer.create(
      amount: reversal.amount,
      currency: ::Billing::Stripe::TransferPayments::DEFAULT_CURRENCY,
      destination: reversal.metadata[INTER_ACCOUNT_TRANSFER_KEY],
      transfer_group: transfer.transfer_group,
      metadata: metadata,
    )
  end
end

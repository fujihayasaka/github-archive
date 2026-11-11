# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for creating a sponsorship that uses a one-time tier.
module Sponsors
  class AddOneTimePayment < CreateSponsorship
    # inputs - Hash containing attributes to create a sponsorship
    # inputs[:tier] - the SponsorsTier to be purchased
    # inputs[:sponsor] - the User or Organization who is sponsoring
    # inputs[:sponsorable] - the User or Organization being sponsored; defaults to the sponsorable for the given tier
    # inputs[:viewer] - currently authenticated User
    # inputs[:is_public] - Boolean indicating whether the sponsor's identity should be made public in
    #                      the new sponsorship
    # inputs[:state] - the state of the sponsorship; defaults to "pending"
    # inputs[:email_opt_in] - true if the sponsor would like to receive email updates from the sponsorable
    # inputs[:invoiced_transfer] - An optional `InvoicedSponsorshipTransfer` object used for invoiced sponsorships
    # inputs[:sponsorable_metadata] - An optional Hash of user-given metadata for the sponsorship, data the
    #                                 sponsorable may have specified
    # inputs[:skip_sync] - Boolean allowing the normal plan subscription sync that occurs after subscription item
    #                      creation to be skipped.
    # inputs[:via_bulk_sponsorship] - Boolean indicating whether this sponsorship is being created along with others
    #                                 via our Bulk Sponsorship tool
    #
    # Returns a Sponsorship, a Billing::SubscriptionItem, or raises one of:
    # Sponsors::CreateSponsorship::UnprocessableError, Sponsors::CreateSponsorship::ForbiddenError.
    def self.call(inputs)
      new(**inputs).call
    end

    def initialize(tier:, sponsor:, viewer:, sponsorable: nil, state: :pending, is_public: true, email_opt_in: true, invoiced_transfer: nil, sponsorable_metadata: nil, skip_sync: false, via_bulk_sponsorship: false)
      raise UnprocessableError.new("Did not get a one-time tier") unless tier&.one_time?
      super(
        tier: tier,
        sponsor: sponsor,
        sponsorable: sponsorable,
        viewer: viewer,
        state: state,
        is_public: is_public,
        email_opt_in: email_opt_in,
        pay_prorated: false,
        sponsorable_metadata: sponsorable_metadata,
        skip_sync: skip_sync,
        via_bulk_sponsorship: via_bulk_sponsorship,
      )
      @invoiced_transfer = invoiced_transfer
    end

    def call
      if concurrent_recurring_payment?
        verify_enough_trust_for_sponsorship
        verify_not_processing_one_time_payment

        subscription_item = create_subscription_item
        raise UnprocessableError.new(errors.to_sentence) unless subscription_item
        subscription_item
      else
        super
      end
    end

    private

    attr_reader :invoiced_transfer

    def raise_unless_valid
      super
      verify_invoiced_transfer_for_invoiced_tier
      verify_invoiced_transfer_validity
      verify_not_processing_one_time_payment
    end

    def concurrent_recurring_payment?
      return false unless existing_sponsorship&.active?
      existing_sponsorship&.recurring_payment?
    end

    def verify_invoiced_transfer_for_invoiced_tier
      if invoiced? && invoiced_transfer.blank?
        raise UnprocessableError.new("Could not create invoiced sponsorship: An invoiced transfer is required")
      end
    end

    def verify_invoiced_transfer_validity
      if invoiced? && !invoiced_transfer.valid?
        error_list = invoiced_transfer.errors.full_messages.join(", ")
        raise UnprocessableError.new("Could not create invoiced sponsorship: #{error_list}")
      end
    end

    def verify_not_processing_one_time_payment
      if sponsor.processing_one_time_payment_to?(sponsorable)
        error = "Cannot create new one-time sponsorship while previous one-time payment is still processing"
        raise UnprocessableError.new(error)
      end
    end

    def build_sponsorship
      if invoiced?
        build_invoice_based_sponsorship
      else
        super
      end
    end

    def invoiced?
      return @invoiced if defined?(@invoiced)
      @invoiced = tier.invoiced?
    end

    def build_invoice_based_sponsorship
      sponsorship.invoiced_sponsorship_transfer = invoiced_transfer
      sponsorship.expires_at = expiration_time
      sponsorship.paid_at = invoiced_transfer.transfer_created_at
      # if previously this represented a subscription-based sponsorship, we clear
      # out that stale reference
      sponsorship.subscription_item = nil

      true
    end

    def create_subscription_item_params
      params = super
      params[:via_bulk_sponsorship] = via_bulk_sponsorship?
      params
    end

    def expiration_time
      if invoiced?
        invoiced_transfer.expires_at || Sponsorship.expiration_time
      else
        Sponsorship.expiration_time
      end
    end

    def after_sponsorship_saved
      super
      trigger_payment_complete_for_invoiced_sponsorship
    end

    def trigger_payment_complete_for_invoiced_sponsorship
      # non-invoiced and non-legacy invoiced sponsorships have this event triggered when a
      # Billing::BillingTransaction::LineItem is created
      return unless invoiced?

      sponsorship.instrument_payment_complete(tier_paid: tier, via_bulk_sponsorship: via_bulk_sponsorship?)
    end
  end
end

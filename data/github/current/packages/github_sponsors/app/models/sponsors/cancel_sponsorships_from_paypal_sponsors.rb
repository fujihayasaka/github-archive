# typed: true
# frozen_string_literal: true

module Sponsors
  class CancelSponsorshipsFromPaypalSponsors
    include GitHub::Memoizer

    DATADOG_PREFIX = "sponsors.cancel_sponsorships_from_paypal_sponsors"
    MAX_THROTTLE_RETRIES = 4

    class Result
      attr_reader :cancelled_sponsorships, :failed_sponsorships

      def self.success
        new(cancelled_sponsorships: [], failed_sponsorships: [])
      end

      def initialize(cancelled_sponsorships:, failed_sponsorships:)
        @cancelled_sponsorships = cancelled_sponsorships
        @failed_sponsorships = failed_sponsorships
      end

      def success?
        failed_sponsorships.empty?
      end
    end

    # Public: Cancel sponsorships for billable entities who have PayPal as their chosen payment method for
    # sponsorships.
    #
    # billable_entities - a single User, Organization, and Business or an Array of them whose sponsorships should
    #                     potentially be cancelled
    #
    # Returns a Sponsors::CancelSponsorshipsFromPaypalSponsors::Result.
    def self.call(billable_entities)
      new(billable_entities).call
    end

    def initialize(billable_entities)
      @billable_entities = Array.wrap(billable_entities)
      @failed_sponsorships = []
      @cancelled_sponsorships = []
    end

    def call
      return Result.success unless GitHub.sponsors_enabled?
      return Result.success if billable_entities.empty? || sponsorships_to_cancel.empty?

      cancel_sponsorships
      email_sponsors

      Result.new(cancelled_sponsorships: cancelled_sponsorships, failed_sponsorships: failed_sponsorships)
    end

    private

    attr_reader :billable_entities, :failed_sponsorships, :cancelled_sponsorships

    def cancel_sponsorships
      throttle_writes do
        sponsorships_to_cancel.each do |sponsorship|
          sponsor = sponsorship.sponsor
          datadog_tags = ["sponsor_type:#{sponsor.type}"]

          result = sponsorship.cancel(actor: User.staff_user, reason: :PAYPAL_DEPRECATION, force: true)

          if result.success
            GitHub.dogstats.increment("#{DATADOG_PREFIX}.sponsorship_cancelled", tags: datadog_tags)
            cancelled_sponsorships << sponsorship
          else
            GitHub.dogstats.increment("#{DATADOG_PREFIX}.sponsorship_cancellation_failure", tags: datadog_tags)
            failed_sponsorships << sponsorship
          end
        end
      end

      is_success = failed_sponsorships.empty?
      GitHub.dogstats.increment(DATADOG_PREFIX, tags: ["success:#{is_success}"])
    end

    def email_sponsors
      sorted_cancelled_sponsorships = cancelled_sponsorships.sort_by(&:id)
      cancelled_sponsorships_by_sponsor = sorted_cancelled_sponsorships.each_with_object({}) do |sponsorship, hash|
        hash[sponsorship.sponsor] ||= []
        hash[sponsorship.sponsor] << sponsorship
      end
      cancelled_sponsorships_by_sponsor.each do |sponsor, cancelled_sponsorships|
        SponsorsPrimerMailer.sponsors_cancelled_paypal_sponsorships_notice(sponsor: sponsor,
          sponsorships: cancelled_sponsorships).deliver_later
      end
    end

    memoize def paypal_billable_entities
      result = billable_entities.select do |billable_entity|
        billable_entity.user? || billable_entity.organization? # businesses can't sponsor, so exclude them
      end
      return [] if result.empty?

      GitHub::PrefillAssociations.prefill_associations(result, { customers: :payment_method })
      result.reject(&:has_valid_payment_method_for_sponsorships?) # if we know how to charge them, we're good
        .select(&:has_paypal_account_for_sponsors?) # specifically PayPal users since that's deprecated for Sponsors
    end

    memoize def sponsorships_to_cancel
      GitHub::PrefillAssociations.prefill_batch_method(paypal_billable_entities, :active_sponsorships_as_sponsor,
        { scope: Sponsorship.recurring })
      sponsorships = paypal_billable_entities.flat_map do |billable_entity|
        billable_entity.active_sponsorships_as_sponsor(scope: Sponsorship.recurring)
      end
      GitHub::PrefillAssociations.prefill_associations(sponsorships, :sponsor,
        available_records: paypal_billable_entities)

      # Used with Hydro instrumentation upon cancelling, see Sponsorship#instrument_cancel:
      GitHub::PrefillAssociations.prefill_associations(sponsorships, [:sponsors_listing, :tier,
        :sponsors_listing_stafftools_metadata, :invoiced_sponsorship_transfer, { subscription_item: :customer }])
      GitHub::PrefillAssociations.prefill_batch_method(sponsorships, :active_goal)

      sponsorships
    end

    def throttle_writes(&block)
      throttle_sponsors_writes do
        throttle_users_writes(&block)
      end
    end

    def throttle_sponsors_writes(&block)
      ApplicationRecord::Domain::Sponsors.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, &block)
    rescue Freno::Throttler::Error => e
      GitHub.dogstats.increment("#{DATADOG_PREFIX}.throttle_with_retry.error",
        tags: ["retry:#{MAX_THROTTLE_RETRIES}"])
      raise e, "Exhausted throttler retries for Sponsors domain (#{MAX_THROTTLE_RETRIES} times)."
    end

    def throttle_users_writes(&block)
      ApplicationRecord::Domain::Users.throttle_writes_with_retry(max_retry_count: MAX_THROTTLE_RETRIES, &block)
    rescue Freno::Throttler::Error => e
      GitHub.dogstats.increment("#{DATADOG_PREFIX}.throttle_with_retry.error",
        tags: ["retry:#{MAX_THROTTLE_RETRIES}"])
      raise e, "Exhausted throttler retries for Users domain (#{MAX_THROTTLE_RETRIES} times)."
    end
  end
end

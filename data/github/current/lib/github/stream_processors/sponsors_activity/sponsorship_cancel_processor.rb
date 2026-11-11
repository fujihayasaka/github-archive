# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SponsorsActivity
      class SponsorshipCancelProcessor < SingleMessageProcessor
        default_to_write_connection!

        include TransientErrorResiliency

        DEFAULT_GROUP_ID = "sponsors_activity_cancel"
        DEFAULT_SUBSCRIBE_TO = /sponsors.v1.SponsorshipCreateCancel\Z/

        # Minimum number of cancellations by a single sponsor within the lookback window
        # to trigger a fraud review for the maintainer's listing.
        CANCELLATION_FRAUD_THRESHOLD = 3

        # Time window in which repeated cancellations are considered suspicious.
        CANCELLATION_FRAUD_LOOKBACK = 7.days

        options[:min_bytes] = 1
        options[:max_wait_time] = 1.second
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false
        options[:max_bytes_per_partition] = 100.kilobytes

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "sponsors_activity_processor.sponsorship_cancel"
        end

        def process_message(message)
          action = message.value[:action]
          return message.skip("not_cancel_action") unless action == :CANCEL

          sponsorship = sponsorship_for(message)
          return message.skip("sponsorship_not_paid") unless sponsorship.paid?

          # Exclude one-time, non-invoiced sponsorships because we don't provide a way for users to 'cancel' them.
          # Invoiced sponsorships have a 'one-time' tier but they may recur despite that, and they can be cancelled
          # in stafftools.
          unless sponsorship.recurring_or_invoiced_payment?
            return message.skip("sponsorship_not_recurring_or_invoiced")
          end

          # Check to see if this old-style invoiced sponsorship was meant to be a one-off or if it was meant to
          # recur. If it was meant to recur, we want to acknowledge a cancellation by creating a new
          # SponsorsActivity, but if it was only meant to be that one payment, it's confusing to have a cancellation
          # activity log.
          if sponsorship.manual_invoiced? && !sponsorship.manually_invoiced_consecutive_recurrence?
            return message.skip("sponsorship_not_consecutive_recurring_invoiced")
          end

          attrs = activity_attrs(message)

          ::SponsorsActivity.throttle_with_retry(max_retry_count: 5) do
            safe_trigger_heartbeat
            ::SponsorsActivity.create!(attrs)
          end

          begin
            check_cancellation_fraud_pattern(attrs[:sponsor_id], attrs[:sponsorable_id])
          rescue => e
            Failbot.report(e, context: {
              processor: self.class.name,
              sponsor_id: attrs[:sponsor_id],
              sponsorable_id: attrs[:sponsorable_id],
            })
          end
        end

        def activity_attrs(message)
          data = message.value
          sponsorable_id = data.dig(:sponsorship, :maintainer, :id)
          sponsor_id = data.dig(:sponsorship, :sponsor, :id)
          sponsors_tier_id = data.dig(:tier, :id)
          matchable = data[:matchable]
          repository_id = data.dig(:tier, :repository_id)
          invoiced = data[:invoiced]
          payment_source = payment_source_for(data[:payment_source])

          {
            timestamp: Time.at(message.timestamp),
            sponsorable_id: sponsorable_id,
            sponsor_id: sponsor_id,
            sponsors_tier_id: sponsors_tier_id,
            action: :cancelled_sponsorship,
            matched_sponsorship: matchable,
            invoiced: invoiced,
            repository_id: repository_id,
            payment_source: payment_source,
          }
        end

        def sponsorship_for(message)
          sponsorship_id = message.value[:sponsorship][:id]
          Sponsorship.find_by!(id: sponsorship_id)
        end

        def payment_source_for(raw_payment_source)
          payment_source = raw_payment_source.to_s.downcase # :GITHUB => "github"
          return payment_source.to_sym if ::SponsorsActivity.payment_sources.key?(payment_source)
          :github
        end

        # Private: After recording a cancellation activity, check if the sponsor has cancelled
        # sponsorships repeatedly within a short time window. If the threshold is met, enqueue
        # the maintainer's listing for fraud review.
        #
        # Two checks are performed:
        #   1. Per-(sponsor, sponsorable) pair: 3+ cancellations to the same maintainer in 7 days.
        #   2. Per-sponsor global: 3+ cancellations to any maintainer in 7 days.
        #
        # Both checks are skipped when the sponsor is hammy, since hammy funders are trusted
        # good actors and any cancellation pattern is expected to be legitimate.
        def check_cancellation_fraud_pattern(sponsor_id, sponsorable_id)
          return unless FeatureFlag.vexi.enabled?(:sponsors_cancellation_fraud_detection, default: false)
          return if sponsor_id.blank? || sponsorable_id.blank?

          # Skip if the funder is hammy — they've been verified as a legitimate actor.
          sponsor = ::SponsorsActivity.find_by(sponsor_id: sponsor_id)&.sponsor
          return if sponsor&.hammy?

          cutoff = CANCELLATION_FRAUD_LOOKBACK.ago

          # Check 1: Per-(sponsor, maintainer) repeated cancellations
          per_pair_count = ::SponsorsActivity
            .where(sponsor_id: sponsor_id, sponsorable_id: sponsorable_id, action: :cancelled_sponsorship)
            .where("timestamp >= ?", cutoff)
            .count

          if per_pair_count >= CANCELLATION_FRAUD_THRESHOLD
            enqueue_fraud_review_for_sponsorable(sponsorable_id)
          end

          # Check 2: Per-sponsor global cancellations across all maintainers
          global_count = ::SponsorsActivity
            .where(sponsor_id: sponsor_id, action: :cancelled_sponsorship)
            .where("timestamp >= ?", cutoff)
            .count

          if global_count >= CANCELLATION_FRAUD_THRESHOLD
            enqueue_fraud_reviews_for_sponsor_targets(sponsor_id, cutoff)
          end
        end

        # Private: Create a fraud review for the listing of the given sponsorable,
        # unless the sponsorable is hammy or spammy, or there is already a pending,
        # flagged, or resolved review.
        def enqueue_fraud_review_for_sponsorable(sponsorable_id)
          listing = ::SponsorsListing.find_by(sponsorable_id: sponsorable_id)
          return unless listing

          # Skip hammy sponsorables — already verified as legitimate users.
          # Skip spammy sponsorables — Platform Health already manages their listings.
          sponsorable = listing.sponsorable
          return if sponsorable&.hammy?
          return if sponsorable&.spammy?

          listing.with_lock do
            most_recent_review = listing.fraud_reviews.order(id: :desc).first
            next if most_recent_review && (most_recent_review.pending? || most_recent_review.flagged? || most_recent_review.resolved?)

            ::SponsorsFraudReview.create!(sponsors_listing_id: listing.id)
          end
        end

        # Private: For a sponsor who has hit the global threshold, create fraud reviews for
        # all maintainer listings they have cancelled sponsorships to within the lookback window.
        def enqueue_fraud_reviews_for_sponsor_targets(sponsor_id, cutoff)
          sponsorable_ids = ::SponsorsActivity
            .where(sponsor_id: sponsor_id, action: :cancelled_sponsorship)
            .where("timestamp >= ?", cutoff)
            .distinct
            .pluck(:sponsorable_id)

          sponsorable_ids.each_slice(100) do |batch_ids|
            safe_trigger_heartbeat
            batch_ids.each do |sid|
              enqueue_fraud_review_for_sponsorable(sid)
            end
          end
        end
      end
    end
  end
end

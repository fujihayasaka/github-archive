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
      end
    end
  end
end

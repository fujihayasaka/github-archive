# typed: true
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module SponsorsActivity
      class SponsorshipPaymentCompleteProcessor < BaseProcessor
        default_to_write_connection!

        include TransientErrorResiliency

        DEFAULT_GROUP_ID = "sponsors_activity_payment_complete"
        DEFAULT_SUBSCRIBE_TO = /sponsors.v1.SponsorshipPaymentComplete\Z/

        options[:min_bytes] = 1
        options[:max_wait_time] = 1.second
        options[:session_timeout] = 60.seconds
        options[:socket_timeout] = 65.seconds
        options[:start_from_beginning] = false
        options[:max_bytes_per_partition] = 100.kilobytes

        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          self.metric_prefix = "sponsors_activity_processor.sponsorship_payment_complete"
        end

        # message - contains data matching lib/hydro/schemas/github/sponsors/v1/sponsorship_payment_complete_pb.rb
        def process_message(message)
          first_payment = message.value[:first_payment]
          return message.skip("not_first_payment") unless first_payment

          attrs = activity_attrs(message)

          ::SponsorsActivity.throttle_with_retry(max_retry_count: 5) do
            safe_trigger_heartbeat
            ::SponsorsActivity.create!(attrs)
          end

          sponsorship_id = message.value[:sponsorship][:id]
          sponsorship = with_read { Sponsorship.includes(:sponsor, :sponsors_listing).find_by(id: sponsorship_id) }

          # Update featured sponsors
          AutoUpdateFeaturedSponsorsJob.perform_later(sponsorship.sponsors_listing)

          if GitHub.flipper[:sponsors_pending_sponsorships].enabled?(sponsorship&.sponsor)
            ::Sponsorship.throttle_with_retry(max_retry_count: 5) do
              safe_trigger_heartbeat
              sponsorship.payment_completed!
            end
          end
        end

        private

        # message - contains data matching lib/hydro/schemas/github/sponsors/v1/sponsorship_payment_complete_pb.rb
        #
        # Returns a Hash for creating a SponsorsActivity.
        def activity_attrs(message)
          data = message.value
          sponsorable_id = data.dig(:sponsorship, :maintainer, :id)
          sponsor_id = data.dig(:sponsorship, :sponsor, :id)
          sponsors_tier_id = data.dig(:tier, :id)
          matchable = data[:matchable]
          sponsorable_metadata = data.dig(:sponsorship, :sponsorable_metadata)
          repository_id = repo_id_sponsorship_grants_access_to(tier_id: sponsors_tier_id, sponsor_id: sponsor_id)
          invoiced = data[:invoiced]
          via_bulk_sponsorship = data[:via_bulk_sponsorship]
          payment_source = data[:payment_source].to_s.downcase.to_sym # :GITHUB => :github

          {
            timestamp: Time.at(message.timestamp),
            sponsorable_id: sponsorable_id,
            sponsor_id: sponsor_id,
            sponsors_tier_id: sponsors_tier_id,
            action: :new_sponsorship,
            matched_sponsorship: matchable,
            sponsorable_metadata: sponsorable_metadata,
            invoiced: invoiced,
            repository_id: repository_id,
            via_bulk_sponsorship: via_bulk_sponsorship,
            payment_source: payment_source,
          }
        end

        def repo_id_sponsorship_grants_access_to(tier_id:, sponsor_id:)
          tier = SponsorsTier.find_by(id: tier_id)
          return unless tier

          sponsor = User.find_by(id: sponsor_id)
          return unless sponsor

          tier.repository_id_for_sponsor(sponsor)
        end
      end
    end
  end
end

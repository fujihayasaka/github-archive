# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillIdentityOnBundledLicenseAssignments < Base

      class BundledLicenseAssignment < ApplicationRecord::Domain::Billing
        self.table_name = :bundled_license_assignments
      end

      iterate_over :database_table, params: {
        model_class: BundledLicenseAssignment,
        columns: %i[subscription_id],
      }

      # Strategy:
      # 1. Generate list of unique subscription IDs from the bundled license assignments in the batch
      # 2. For each subscription ID, fetch the VSS events ordered by last_modified_at (most recent appear first in list)
      # 3. For each bundled license assignment in the batch, find the most recent VSS assign event that matches the email
      # 4. Update the identity of the bundled license assignment with the email from the most recent event
      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        subscription_ids = items.values.map { |bla| bla[:subscription_id] }.uniq

        subscription_feeds = {}
        subscription_ids.each do |subscription_id|
          events = ::Licensing::Vss::VssSubscriptionEvent.where(subscription_id: subscription_id).order(last_modified_date: :desc)
          subscription_feeds[subscription_id] = events.to_a
        end

        batch_bla_ids = items.keys.uniq

        log "#{dry_run? ? "Would be backfilling" : "Backfilling"} identity for bundled license assignment IDs: #{batch_bla_ids.join(', ')}"

        BundledLicenseAssignment.where(id: batch_bla_ids).each do |bla|
          subscription_feed = subscription_feeds[bla.subscription_id]

          if subscription_feed.blank?
            log "No VSS events found for bundled license assignment ID: #{bla.id}, skipping."
            next
          end

          most_recent_bla_identity = subscription_feed
            .find { |event| event.email&.downcase == bla.email&.downcase && event.new_assignment? }&.identity

          if most_recent_bla_identity.blank?
            log "No matching email found in VSS subscription feed for bundled license assignment ID: #{bla.id}, skipping."
            next
          end

          if dry_run?
            log "Backfill bundled license assignment ID #{bla.id} with identity #{most_recent_bla_identity}"
            next
          end

          write_to(model_class: BundledLicenseAssignment) do
            bla.update!(identity: most_recent_bla_identity)
          end
        end
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillIdentityOnBundledLicenseAssignments.new(args).run
end

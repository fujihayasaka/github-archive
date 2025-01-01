# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class VssJsonPayloadBackfill < Base
      class VssSubscriptionEvent < ApplicationRecord::Domain::Billing
        self.table_name = :vss_subscription_events
      end

      iterate_over :database_table, params: {
        model_class: VssSubscriptionEvent,
        columns: %i[id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        batch_event_ids = items.keys.uniq

        log "Backfilling VSS subscription events with IDs: #{batch_event_ids.join(', ')}"

        backfill_events = VssSubscriptionEvent.where(id: batch_event_ids)

        backfill_events.each do |event|
          log "#{dry_run? ? "Would be backfilling" : "Backfilling"} VSS subscription event #{event.id}"

          parsed_payload = nil
          begin
            parsed_payload = JSON.parse(event.payload)
            log "Valid payload for event ID #{event.id}"
          rescue StandardError => e
            log "Failed to parse payload for event ID #{event.id}: #{e.message}"
            log "Skip event ID #{event.id}"
            next
          end

          next if dry_run?

          write_to(model_class: VssSubscriptionEvent) do
            event.update!(parsed_payload:)
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

  GitHub::Transitions::VssJsonPayloadBackfill.new(args).run
end
